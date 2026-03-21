"""
Workers Celery – Tâches asynchrones pour le traitement des paiements.

Ces tâches s'exécutent en arrière-plan (via Redis Broker).
Si le réseau Wave/Orange est lent ou down, la tâche est replanifiée
automatiquement – l'application ne "plante" jamais.
"""
from datetime import datetime, timedelta
from celery import shared_task
from celery.utils.log import get_task_logger

logger = get_task_logger(__name__)


@shared_task(
    bind=True,
    max_retries=5,
    default_retry_delay=60,  # Réessayer après 60s si échec réseau
    name="workers.envoyer_push_paiement"
)
def envoyer_push_paiement(
    self,
    contrat_id: str,
    montant: float,
    operateur: str,
    telephone_client: str,
    reference_interne: str
):
    """
    Envoie une demande de paiement Push Mobile Money.
    Réessaie automatiquement en cas de réseau instable (max 5 fois).
    """
    from app import create_app, get_mongo_db
    from app.services.mobile_money import get_service_mobile_money

    app = create_app()
    with app.app_context():
        try:
            service = get_service_mobile_money(operateur)
            resultat = service.envoyer_demande_paiement(
                telephone_client=telephone_client,
                montant=montant,
                reference_interne=reference_interne,
                description=f"Remboursement crédit – Réf {reference_interne[:8]}"
            )

            # Enregistrer la tentative dans MongoDB
            mongo = get_mongo_db()
            mongo.flux_paiements.update_one(
                {"contrat_id": contrat_id},
                {
                    "$push": {
                        "transactions": {
                            "date": datetime.utcnow(),
                            "montant": montant,
                            "source": operateur,
                            "reference_api": resultat.reference,
                            "statut": "EN_ATTENTE" if resultat.succes else "ECHEC",
                            "message": resultat.message,
                        }
                    },
                    "$setOnInsert": {"contrat_id": contrat_id, "client_id": ""},
                },
                upsert=True
            )

            if not resultat.succes:
                # Si l'API Mobile Money a refusé (pas un timeout) = on ne réessaie pas
                if "Timeout" in resultat.message or "Réseau" in resultat.message:
                    raise self.retry(exc=Exception(resultat.message))
                logger.error(f"Paiement refusé pour contrat {contrat_id}: {resultat.message}")

            logger.info(f"Push paiement {operateur} envoyé – Ref: {resultat.reference}")
            return resultat.to_dict()

        except Exception as exc:
            logger.warning(f"Tentative {self.request.retries + 1}/5 – {exc}")
            raise self.retry(exc=exc)


@shared_task(name="workers.verifier_contrats_en_retard")
def verifier_contrats_en_retard():
    """
    Tâche périodique (cron Celery Beat) – s'exécute à minuit.
    Vérifie tous les contrats actifs et marque ceux en retard.
    Envoie des alertes WhatsApp aux clients concernés.
    """
    from app import create_app
    from app.models.contrat import ContratCredit, StatutContrat
    from app.models.client import Client
    from app.services.notifications import WhatsAppService
    from app import db

    app = create_app()
    with app.app_context():
        maintenant = datetime.utcnow()
        contrats_actifs = ContratCredit.query.filter_by(statut=StatutContrat.ACTIF).all()
        whatsapp = WhatsAppService()
        nb_retards = 0

        for contrat in contrats_actifs:
            if contrat.date_echeance < maintenant:
                contrat.statut = StatutContrat.EN_RETARD
                contrat.nombre_retards += 1
                nb_retards += 1

                # Alerte WhatsApp
                client = Client.query.get(contrat.client_id)
                if client:
                    whatsapp.envoyer_alerte_retard(
                        telephone=client.telephone,
                        nom_client=client.nom_complet,
                        montant_du=float(contrat.montant_restant)
                    )
                    # Recalcul score (pénalité retard)
                    recalculer_score_client.delay(str(client.id))

        db.session.commit()
        logger.info(f"Vérification retards : {nb_retards} contrats marqués EN_RETARD")
        return {"contrats_en_retard": nb_retards}


@shared_task(name="workers.envoyer_rappels_quotidiens")
def envoyer_rappels_quotidiens():
    """
    Envoie des rappels WhatsApp aux clients dont l'échéance est dans 24h.
    Planifié à 18h chaque soir (heure Abidjan).
    """
    from app import create_app
    from app.models.contrat import ContratCredit, StatutContrat
    from app.models.client import Client
    from app.services.notifications import WhatsAppService

    app = create_app()
    with app.app_context():
        demain = datetime.utcnow() + timedelta(hours=24)
        hier = datetime.utcnow()

        contrats_proches = ContratCredit.query.filter(
            ContratCredit.statut == StatutContrat.ACTIF,
            ContratCredit.date_echeance.between(hier, demain)
        ).all()

        whatsapp = WhatsAppService()
        for contrat in contrats_proches:
            client = Client.query.get(contrat.client_id)
            if client:
                whatsapp.envoyer_rappel_paiement(
                    telephone=client.telephone,
                    nom_client=client.nom_complet,
                    montant_du=float(contrat.montant_restant),
                    date_limite=contrat.date_echeance.strftime("%d/%m/%Y")
                )

        logger.info(f"Rappels envoyés à {len(contrats_proches)} clients")


@shared_task(name="workers.recalculer_score_client")
def recalculer_score_client(client_id: str):
    """Recalcule le score d'un client en arrière-plan (après chaque paiement)."""
    from app import create_app
    from app.services.scoring import ScoringService

    app = create_app()
    with app.app_context():
        ScoringService().calculer_score_complet(client_id)
        logger.info(f"Score recalculé pour client {client_id}")


@shared_task(name="workers.programmer_flux_quotidiens")
def programmer_flux_quotidiens():
    """
    À 19h30 chaque soir, programme les Push de paiement automatiques
    pour tous les contrats en mode FLUX_QUOTIDIEN.
    """
    from app import create_app
    from app.models.contrat import ContratCredit, StatutContrat, TypeRemboursement
    from app.models.client import Client
    import uuid

    app = create_app()
    with app.app_context():
        contrats_flux = ContratCredit.query.filter_by(
            statut=StatutContrat.ACTIF,
            type_remboursement=TypeRemboursement.FLUX_QUOTIDIEN
        ).all()

        programmes = 0
        for contrat in contrats_flux:
            if not contrat.montant_flux_quotidien:
                continue

            client = Client.query.get(contrat.client_id)
            if not client:
                continue

            telephone = client.get_numero_mobile_money(contrat.operateur_mm or "wave")
            if not telephone:
                continue

            # Envoyer le Push avec un délai de 30 minutes (à 20h)
            envoyer_push_paiement.apply_async(
                args=[
                    str(contrat.id),
                    float(contrat.montant_flux_quotidien),
                    contrat.operateur_mm or "wave",
                    telephone,
                    str(uuid.uuid4()),
                ],
                countdown=1800  # Dans 30 minutes
            )
            programmes += 1

        logger.info(f"Flux quotidiens programmés : {programmes} contrats")
