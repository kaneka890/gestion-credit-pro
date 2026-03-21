import uuid
from datetime import datetime
from app import db


class StatutContrat:
    ACTIF = "ACTIF"
    EN_RETARD = "EN_RETARD"
    SOLDE = "SOLDE"
    LITIGE = "LITIGE"
    REFUSE = "REFUSE"


class TypeRemboursement:
    FLUX_QUOTIDIEN = "FLUX_QUOTIDIEN"    # Ex: 500 FCFA/jour pendant 20 jours
    ECHEANCES = "ECHEANCES"              # Ex: 3 versements mensuels
    LIBRE = "LIBRE"                      # Le client paie quand il veut (max date_echeance)


class ContratCredit(db.Model):
    """
    Le contrat légal entre un commerçant et son client.
    Stocké en SQL (PostgreSQL) pour les propriétés ACID.
    Les transactions réelles sont dans MongoDB (flux_paiements).
    """
    __tablename__ = "contrats_credit"

    id = db.Column(db.UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    # Parties
    commercant_id = db.Column(
        db.UUID(as_uuid=True),
        db.ForeignKey("commercants.id"),
        nullable=False
    )
    client_id = db.Column(
        db.UUID(as_uuid=True),
        db.ForeignKey("clients.id"),
        nullable=False
    )

    # Montants
    montant_initial = db.Column(db.Numeric(15, 2), nullable=False)
    montant_rembourse = db.Column(db.Numeric(15, 2), default=0.00)
    montant_restant = db.Column(db.Numeric(15, 2), nullable=False)
    taux_service = db.Column(db.Numeric(5, 2), default=0.00)  # % frais plateforme

    # Remboursement
    type_remboursement = db.Column(db.String(30), default=TypeRemboursement.FLUX_QUOTIDIEN)
    montant_flux_quotidien = db.Column(db.Numeric(10, 2))  # Si FLUX_QUOTIDIEN
    heure_prelevement = db.Column(db.Time)                 # Ex: 20:00 chaque soir

    # Dates
    date_creation = db.Column(db.DateTime, default=datetime.utcnow)
    date_echeance = db.Column(db.DateTime, nullable=False)
    date_solde = db.Column(db.DateTime)

    # Statut
    statut = db.Column(db.String(20), default=StatutContrat.ACTIF)
    nombre_retards = db.Column(db.Integer, default=0)

    # Opérateur Mobile Money préféré pour ce contrat
    operateur_mm = db.Column(db.String(20))  # 'wave', 'orange', 'mtn'

    # Signature digitale = hash du code PIN USSD (ne jamais stocker le PIN lui-même)
    signature_digitale_id = db.Column(db.String(255))

    # Objet du crédit (ex: "Sacs de riz", "Tissu wax 10m")
    description = db.Column(db.String(500))

    # Score au moment de l'octroi (audit trail)
    score_au_moment_octroi = db.Column(db.Integer)

    def est_en_retard(self) -> bool:
        return datetime.utcnow() > self.date_echeance and self.statut == StatutContrat.ACTIF

    def pourcentage_rembourse(self) -> float:
        if self.montant_initial == 0:
            return 0.0
        return float(self.montant_rembourse / self.montant_initial * 100)

    def to_dict(self):
        return {
            "id": str(self.id),
            "commercant_id": str(self.commercant_id),
            "client_id": str(self.client_id),
            "montant_initial": float(self.montant_initial),
            "montant_rembourse": float(self.montant_rembourse),
            "montant_restant": float(self.montant_restant),
            "taux_service": float(self.taux_service),
            "type_remboursement": self.type_remboursement,
            "montant_flux_quotidien": float(self.montant_flux_quotidien) if self.montant_flux_quotidien else None,
            "statut": self.statut,
            "operateur_mm": self.operateur_mm,
            "description": self.description,
            "date_creation": self.date_creation.isoformat(),
            "date_echeance": self.date_echeance.isoformat(),
            "pourcentage_rembourse": self.pourcentage_rembourse(),
            "score_au_moment_octroi": self.score_au_moment_octroi,
        }
