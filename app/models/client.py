import uuid
from datetime import datetime
from app import db


class Client(db.Model):
    """
    Client du commerçant. Son Score de Réputation lui appartient
    et peut être consulté par plusieurs commerçants (avec permission).
    """
    __tablename__ = "clients"

    id = db.Column(db.UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    nom_complet = db.Column(db.String(200), nullable=False)
    telephone = db.Column(db.String(20), unique=True, nullable=False)

    # Numéros Mobile Money du client (pour les Push de paiement)
    wave_numero = db.Column(db.String(20))
    orange_money_numero = db.Column(db.String(20))
    mtn_momo_numero = db.Column(db.String(20))

    # Identité
    quartier_residence = db.Column(db.String(100))
    photo_url = db.Column(db.String(500))  # Selfie pour KYC léger
    cni_numero = db.Column(db.String(50))  # Carte Nationale d'Identité (optionnel)

    # Garant (optionnel – booste le score de 15%)
    garant_telephone = db.Column(db.String(20))
    garant_nom = db.Column(db.String(200))

    # Lien vers le commerçant qui a créé ce profil
    commercant_id = db.Column(
        db.UUID(as_uuid=True),
        db.ForeignKey("commercants.id"),
        nullable=False
    )

    date_creation = db.Column(db.DateTime, default=datetime.utcnow)
    est_actif = db.Column(db.Boolean, default=True)

    # Relations
    contrats = db.relationship("ContratCredit", backref="client", lazy="dynamic")
    score = db.relationship("ScoreReputation", backref="client", uselist=False)

    def get_numero_mobile_money(self, operateur: str) -> str | None:
        """Retourne le numéro pour l'opérateur donné (wave, orange, mtn)."""
        mapping = {
            "wave": self.wave_numero,
            "orange": self.orange_money_numero,
            "mtn": self.mtn_momo_numero,
        }
        return mapping.get(operateur.lower())

    def to_dict(self):
        return {
            "id": str(self.id),
            "nom_complet": self.nom_complet,
            "telephone": self.telephone,
            "quartier_residence": self.quartier_residence,
            "a_garant": bool(self.garant_telephone),
            "date_creation": self.date_creation.isoformat(),
        }
