from datetime import datetime, timedelta
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.contrat import ContratCredit, StatutContrat, TypeRemboursement
from app.models.client import Client
from app.models.score import ScoreReputation
from app.services.scoring import ScoringService
from app.services.notifications import WhatsAppService

contrats_bp = Blueprint("contrats", __name__)


@contrats_bp.route("", methods=["POST"])
@jwt_required()
def creer_contrat():
    """
    Crée un nouveau contrat de crédit.
    Vérifie d'abord le score du client avant d'accorder le crédit.
    """
    commercant_id = get_jwt_identity()
    data = request.get_json()

    # Validation des champs obligatoires
    champs_requis = ["client_id", "montant_initial", "date_echeance", "operateur_mm"]
    for champ in champs_requis:
        if not data.get(champ):
            return jsonify({"erreur": f"Champ requis : {champ}"}), 400

    montant = float(data["montant_initial"])

    # Vérifier que le client appartient à ce commerçant
    client = Client.query.filter_by(
        id=data["client_id"],
        commercant_id=commercant_id
    ).first()
    if not client:
        return jsonify({"erreur": "Client introuvable pour ce commerçant"}), 404

    # === SCORING : Le client peut-il obtenir ce crédit ? ===
    scoring = ScoringService()
    decision = scoring.peut_obtenir_credit(data["client_id"], montant)

    if not decision["autorise"]:
        return jsonify({
            "erreur": "Crédit refusé",
            "raison": decision["raison"],
            "score": decision["score"],
            "plafond_autorise": decision["plafond"],
        }), 403

    # Parse date d'échéance
    try:
        date_echeance = datetime.fromisoformat(data["date_echeance"])
    except ValueError:
        return jsonify({"erreur": "Format date_echeance invalide (ISO 8601 requis : YYYY-MM-DDTHH:MM:SS)"}), 400

    if date_echeance <= datetime.utcnow():
        return jsonify({"erreur": "La date d'échéance doit être dans le futur"}), 400

    # Créer le contrat
    type_remb = data.get("type_remboursement", TypeRemboursement.FLUX_QUOTIDIEN)
    contrat = ContratCredit(
        commercant_id=commercant_id,
        client_id=data["client_id"],
        montant_initial=montant,
        montant_restant=montant,
        taux_service=float(data.get("taux_service", 0.0)),
        type_remboursement=type_remb,
        montant_flux_quotidien=float(data["montant_flux_quotidien"]) if data.get("montant_flux_quotidien") else None,
        date_echeance=date_echeance,
        operateur_mm=data["operateur_mm"].lower(),
        description=data.get("description", ""),
        score_au_moment_octroi=decision["score"],
        statut=StatutContrat.ACTIF,
    )

    db.session.add(contrat)
    db.session.commit()

    # Notification WhatsApp au client
    WhatsAppService().envoyer_contrat_cree(
        telephone=client.telephone,
        nom_client=client.nom_complet,
        montant=montant,
        date_echeance=date_echeance.strftime("%d/%m/%Y"),
    )

    # Si flux quotidien activé immédiatement
    if type_remb == TypeRemboursement.FLUX_QUOTIDIEN and data.get("demarrer_flux_maintenant"):
        from app.workers.payment_worker import envoyer_push_paiement
        import uuid
        telephone_mm = client.get_numero_mobile_money(contrat.operateur_mm)
        if telephone_mm and contrat.montant_flux_quotidien:
            envoyer_push_paiement.delay(
                str(contrat.id),
                float(contrat.montant_flux_quotidien),
                contrat.operateur_mm,
                telephone_mm,
                str(uuid.uuid4()),
            )

    return jsonify({
        "message": "Contrat créé avec succès",
        "contrat": contrat.to_dict(),
        "decision_credit": decision,
    }), 201


@contrats_bp.route("", methods=["GET"])
@jwt_required()
def lister_contrats():
    """Liste les contrats du commerçant avec filtres optionnels."""
    commercant_id = get_jwt_identity()
    statut = request.args.get("statut")
    client_id = request.args.get("client_id")

    query = ContratCredit.query.filter_by(commercant_id=commercant_id)
    if statut:
        query = query.filter_by(statut=statut.upper())
    if client_id:
        query = query.filter_by(client_id=client_id)

    contrats = query.order_by(ContratCredit.date_creation.desc()).all()

    return jsonify({
        "contrats": [c.to_dict() for c in contrats],
        "total": len(contrats),
    })


@contrats_bp.route("/<contrat_id>", methods=["GET"])
@jwt_required()
def detail_contrat(contrat_id):
    """Détail d'un contrat avec l'historique des paiements (MongoDB)."""
    commercant_id = get_jwt_identity()
    contrat = ContratCredit.query.filter_by(
        id=contrat_id,
        commercant_id=commercant_id
    ).first()

    if not contrat:
        return jsonify({"erreur": "Contrat introuvable"}), 404

    # Récupérer l'historique depuis MongoDB
    from app import get_mongo_db
    mongo = get_mongo_db()
    flux = mongo.flux_paiements.find_one({"contrat_id": str(contrat_id)})
    transactions = flux.get("transactions", []) if flux else []

    # Sérialiser les dates MongoDB
    for tx in transactions:
        if isinstance(tx.get("date"), datetime):
            tx["date"] = tx["date"].isoformat()

    return jsonify({
        "contrat": contrat.to_dict(),
        "historique_paiements": transactions,
        "nb_transactions": len(transactions),
    })


@contrats_bp.route("/<contrat_id>/marquer-solde", methods=["PATCH"])
@jwt_required()
def marquer_solde(contrat_id):
    """Marque manuellement un contrat comme soldé."""
    commercant_id = get_jwt_identity()
    contrat = ContratCredit.query.filter_by(
        id=contrat_id,
        commercant_id=commercant_id
    ).first()

    if not contrat:
        return jsonify({"erreur": "Contrat introuvable"}), 404

    contrat.statut = StatutContrat.SOLDE
    contrat.date_solde = datetime.utcnow()
    contrat.montant_restant = 0
    db.session.commit()

    # Recalculer le score (événement positif)
    from app.workers.payment_worker import recalculer_score_client
    recalculer_score_client.delay(str(contrat.client_id))

    return jsonify({"message": "Contrat marqué comme soldé", "contrat": contrat.to_dict()})


@contrats_bp.route("/<contrat_id>/push-paiement", methods=["POST"])
@jwt_required()
def envoyer_push_manuel(contrat_id):
    """Envoie manuellement un Push de paiement Mobile Money au client."""
    commercant_id = get_jwt_identity()
    data = request.get_json()

    contrat = ContratCredit.query.filter_by(
        id=contrat_id,
        commercant_id=commercant_id
    ).first()
    if not contrat:
        return jsonify({"erreur": "Contrat introuvable"}), 404

    if contrat.statut == StatutContrat.SOLDE:
        return jsonify({"erreur": "Ce contrat est déjà soldé"}), 400

    montant = float(data.get("montant", contrat.montant_flux_quotidien or contrat.montant_restant))
    client = Client.query.get(contrat.client_id)
    telephone = client.get_numero_mobile_money(contrat.operateur_mm)

    if not telephone:
        return jsonify({"erreur": f"Pas de numéro {contrat.operateur_mm} pour ce client"}), 400

    import uuid
    from app.workers.payment_worker import envoyer_push_paiement

    task = envoyer_push_paiement.delay(
        str(contrat.id),
        montant,
        contrat.operateur_mm,
        telephone,
        str(uuid.uuid4()),
    )

    return jsonify({
        "message": "Push de paiement en cours d'envoi",
        "task_id": task.id,
        "operateur": contrat.operateur_mm,
        "montant": montant,
    })
