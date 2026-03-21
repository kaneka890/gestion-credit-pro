import uuid
from datetime import datetime
from app import db
from werkzeug.security import generate_password_hash, check_password_hash


class Commercant(db.Model):
    """Commerçant inscrit sur la plateforme (propriétaire du compte)."""
    __tablename__ = "commercants"

    id = db.Column(db.UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    nom_boutique = db.Column(db.String(200), nullable=False)
    nom_proprietaire = db.Column(db.String(200), nullable=False)
    telephone = db.Column(db.String(20), unique=True, nullable=False)  # +225XXXXXXXXXX
    email = db.Column(db.String(120), unique=True, nullable=True)
    quartier = db.Column(db.String(100))
    ville = db.Column(db.String(100), default="Abidjan")
    password_hash = db.Column(db.String(255), nullable=False)

    # Compte Mobile Money principal du commerçant
    wave_numero = db.Column(db.String(20))
    orange_money_numero = db.Column(db.String(20))
    mtn_momo_numero = db.Column(db.String(20))

    est_actif = db.Column(db.Boolean, default=True)
    date_inscription = db.Column(db.DateTime, default=datetime.utcnow)

    # Relations
    contrats = db.relationship("ContratCredit", backref="commercant", lazy="dynamic")
    clients = db.relationship("Client", backref="commercant_principal", lazy="dynamic")

    def set_password(self, password: str):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password: str) -> bool:
        return check_password_hash(self.password_hash, password)

    def to_dict(self):
        return {
            "id": str(self.id),
            "nom_boutique": self.nom_boutique,
            "nom_proprietaire": self.nom_proprietaire,
            "telephone": self.telephone,
            "quartier": self.quartier,
            "ville": self.ville,
            "date_inscription": self.date_inscription.isoformat(),
        }
