import uuid
from datetime import datetime
from app import db


class ScoreReputation(db.Model):
    """
    Le 'Passeport de Confiance' du client.
    Appartient au client, consultable par les commerçants partenaires.

    Algorithme de scoring :
      - Régularité des paiements  : 40%
      - Ancienneté / fidélité     : 20%
      - Recommandation (garant)   : 15%
      - Vitesse de réponse USSD   : 25%
    """
    __tablename__ = "scores_reputation"

    id = db.Column(db.UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    client_id = db.Column(
        db.UUID(as_uuid=True),
        db.ForeignKey("clients.id"),
        unique=True,
        nullable=False
    )

    # Score global (0 - 100)
    score_global = db.Column(db.Integer, default=50)

    # Composantes du score
    score_regularite = db.Column(db.Integer, default=50)     # Paiements à l'heure
    score_anciennete = db.Column(db.Integer, default=50)     # Durée relation commerciale
    score_recommandation = db.Column(db.Integer, default=0)  # 0 sans garant, 100 avec garant validé
    score_reactivite = db.Column(db.Integer, default=50)     # Temps réponse Push USSD

    # Compteurs bruts (pour recalcul)
    total_contrats = db.Column(db.Integer, default=0)
    contrats_soldes_a_temps = db.Column(db.Integer, default=0)
    contrats_en_retard = db.Column(db.Integer, default=0)
    jours_relation_commerciale = db.Column(db.Integer, default=0)
    temps_moyen_reponse_ussd_sec = db.Column(db.Float, default=0.0)  # secondes

    # Niveau de risque calculé
    niveau_risque = db.Column(db.String(20), default="MOYEN")  # FAIBLE, MOYEN, ELEVE, BLOQUE

    # Limites de crédit autorisées (calculées automatiquement)
    plafond_credit_autorise = db.Column(db.Numeric(12, 2), default=10000.00)

    date_calcul = db.Column(db.DateTime, default=datetime.utcnow)
    date_prochain_recalcul = db.Column(db.DateTime)

    def recalculer(self):
        """Recalcule le score global à partir des composantes."""
        self.score_global = int(
            self.score_regularite * 0.40
            + self.score_anciennete * 0.20
            + self.score_recommandation * 0.15
            + self.score_reactivite * 0.25
        )

        # Niveau de risque
        if self.score_global >= 75:
            self.niveau_risque = "FAIBLE"
            self.plafond_credit_autorise = min(500000, self.score_global * 2000)
        elif self.score_global >= 55:
            self.niveau_risque = "MOYEN"
            self.plafond_credit_autorise = min(100000, self.score_global * 1000)
        elif self.score_global >= 40:
            self.niveau_risque = "ELEVE"
            self.plafond_credit_autorise = min(30000, self.score_global * 500)
        else:
            self.niveau_risque = "BLOQUE"
            self.plafond_credit_autorise = 0

        self.date_calcul = datetime.utcnow()

    def to_dict(self):
        return {
            "client_id": str(self.client_id),
            "score_global": self.score_global,
            "composantes": {
                "regularite": {"score": self.score_regularite, "poids": "40%"},
                "anciennete": {"score": self.score_anciennete, "poids": "20%"},
                "recommandation": {"score": self.score_recommandation, "poids": "15%"},
                "reactivite": {"score": self.score_reactivite, "poids": "25%"},
            },
            "niveau_risque": self.niveau_risque,
            "plafond_credit_autorise": float(self.plafond_credit_autorise),
            "statistiques": {
                "total_contrats": self.total_contrats,
                "soldes_a_temps": self.contrats_soldes_a_temps,
                "en_retard": self.contrats_en_retard,
                "jours_relation": self.jours_relation_commerciale,
            },
            "date_calcul": self.date_calcul.isoformat(),
        }
