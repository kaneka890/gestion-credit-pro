"""
Service de Scoring – Calcul du 'Passeport de Confiance'
Recalcule le score d'un client en temps réel à partir de son historique.
"""
from datetime import datetime, timedelta
from typing import Optional
from app import db, get_mongo_db
from app.models.client import Client
from app.models.contrat import ContratCredit, StatutContrat
from app.models.score import ScoreReputation


class ScoringService:

    def calculer_score_complet(self, client_id: str) -> ScoreReputation:
        """
        Recalcule et sauvegarde le score complet d'un client.
        Appelé après chaque paiement ou à minuit pour mise à jour journalière.
        """
        client = Client.query.get(client_id)
        if not client:
            raise ValueError(f"Client {client_id} introuvable")

        score = ScoreReputation.query.filter_by(client_id=client_id).first()
        if not score:
            score = ScoreReputation(client_id=client_id)
            db.session.add(score)

        # 1. Score Régularité (40%)
        score.score_regularite = self._calculer_regularite(client_id)

        # 2. Score Ancienneté (20%)
        score.score_anciennete = self._calculer_anciennete(client, client_id)

        # 3. Score Recommandation / Garant (15%)
        score.score_recommandation = self._calculer_recommandation(client)

        # 4. Score Réactivité USSD (25%)
        score.score_reactivite = self._calculer_reactivite(client_id)

        # Compteurs bruts
        tous_contrats = ContratCredit.query.filter_by(client_id=client_id).all()
        score.total_contrats = len(tous_contrats)
        score.contrats_soldes_a_temps = sum(
            1 for c in tous_contrats if c.statut == StatutContrat.SOLDE
        )
        score.contrats_en_retard = sum(
            1 for c in tous_contrats if c.statut == StatutContrat.EN_RETARD
        )
        score.jours_relation_commerciale = self._calculer_jours_relation(tous_contrats)

        # Calcul final
        score.recalculer()
        score.date_prochain_recalcul = datetime.utcnow() + timedelta(hours=24)

        db.session.commit()
        return score

    def peut_obtenir_credit(self, client_id: str, montant_demande: float) -> dict:
        """
        Décision rapide : le client peut-il obtenir ce montant ?
        Retourne : { "autorise": bool, "raison": str, "score": int }
        """
        score = ScoreReputation.query.filter_by(client_id=client_id).first()

        if not score:
            # Nouveau client = score de départ à 50
            score = self.calculer_score_complet(client_id)

        from flask import current_app
        score_min = current_app.config.get("MIN_SCORE_POUR_CREDIT", 40)

        if score.niveau_risque == "BLOQUE":
            return {
                "autorise": False,
                "raison": "Score insuffisant – historique de non-paiement",
                "score": score.score_global,
                "plafond": 0,
            }

        if montant_demande > float(score.plafond_credit_autorise):
            return {
                "autorise": False,
                "raison": f"Montant dépasse le plafond autorisé ({score.plafond_credit_autorise:.0f} FCFA)",
                "score": score.score_global,
                "plafond": float(score.plafond_credit_autorise),
            }

        if score.score_global < score_min:
            return {
                "autorise": False,
                "raison": f"Score {score.score_global}/100 inférieur au minimum requis ({score_min})",
                "score": score.score_global,
                "plafond": float(score.plafond_credit_autorise),
            }

        # Vérifier qu'il n'a pas de contrat actif en retard
        contrat_en_retard = ContratCredit.query.filter_by(
            client_id=client_id,
            statut=StatutContrat.EN_RETARD
        ).first()

        if contrat_en_retard:
            return {
                "autorise": False,
                "raison": "Contrat en cours en retard de paiement",
                "score": score.score_global,
                "plafond": 0,
            }

        return {
            "autorise": True,
            "raison": f"Score {score.score_global}/100 – risque {score.niveau_risque}",
            "score": score.score_global,
            "plafond": float(score.plafond_credit_autorise),
        }

    # ---- Méthodes privées de calcul ----------------------------------------

    def _calculer_regularite(self, client_id: str) -> int:
        """
        Analyse les 30 derniers jours de paiements dans MongoDB.
        Un paiement reçu le jour prévu = +5pts, en retard = -5pts.
        """
        mongo = get_mongo_db()
        trente_jours = datetime.utcnow() - timedelta(days=30)

        docs = list(mongo.flux_paiements.find({
            "client_id": str(client_id),
            "date": {"$gte": trente_jours}
        }))

        if not docs:
            return 50  # Pas d'historique = score neutre

        total_flux = sum(len(doc.get("transactions", [])) for doc in docs)
        flux_a_temps = sum(
            1 for doc in docs
            for tx in doc.get("transactions", [])
            if tx.get("statut") == "VALIDE"
        )

        if total_flux == 0:
            return 50

        taux = flux_a_temps / total_flux
        return min(100, int(taux * 100))

    def _calculer_anciennete(self, client: Client, client_id: str) -> int:
        """Plus la relation est ancienne avec ce commerçant, plus le score est élevé."""
        if not client.date_creation:
            return 0

        jours = (datetime.utcnow() - client.date_creation).days

        if jours >= 365:
            return 100
        elif jours >= 180:
            return 80
        elif jours >= 90:
            return 60
        elif jours >= 30:
            return 40
        else:
            return max(10, jours)

    def _calculer_recommandation(self, client: Client) -> int:
        """Présence d'un garant connu = boost de 15%."""
        if client.garant_telephone and client.garant_nom:
            return 100  # Garant renseigné
        return 0

    def _calculer_reactivite(self, client_id: str) -> int:
        """
        Analyse le temps moyen de réponse aux Push USSD (stocké en MongoDB).
        < 30s = 100, < 2min = 70, < 10min = 40, > 10min = 10
        """
        mongo = get_mongo_db()
        docs = list(mongo.flux_paiements.find(
            {"client_id": str(client_id), "temps_reponse_sec": {"$exists": True}},
            sort=[("date", -1)],
            limit=20
        ))

        if not docs:
            return 50

        temps_moyens = [doc["temps_reponse_sec"] for doc in docs if doc.get("temps_reponse_sec")]
        if not temps_moyens:
            return 50

        moyenne = sum(temps_moyens) / len(temps_moyens)

        if moyenne <= 30:
            return 100
        elif moyenne <= 120:
            return 70
        elif moyenne <= 600:
            return 40
        else:
            return 10

    def _calculer_jours_relation(self, contrats: list) -> int:
        if not contrats:
            return 0
        date_plus_ancienne = min(c.date_creation for c in contrats)
        return (datetime.utcnow() - date_plus_ancienne).days
