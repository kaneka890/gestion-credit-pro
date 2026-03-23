from flask import Blueprint, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.models.client import Client
from app.models.contrat import ContratCredit
from app.services.notifications import WhatsAppService

rappels_bp = Blueprint("rappels", __name__)


@rappels_bp.route("/client/<client_id>", methods=["POST"])
@jwt_required()
def envoyer_rappel_client(client_id):
    """Envoyer un rappel de paiement manuel à un client."""
    commercant_id = get_jwt_identity()
    client = Client.query.filter_by(
        id=client_id,
        commercant_id=commercant_id
    ).first()

    if not client:
        return jsonify({"erreur": "Client introuvable"}), 404

    contrats_actifs = ContratCredit.query.filter_by(
        client_id=client_id,
        statut="ACTIF"
    ).all()

    if not contrats_actifs:
        return jsonify({"erreur": "Aucun contrat actif pour ce client"}), 404

    whatsapp = WhatsAppService()
    envoyes = 0
    for contrat in contrats_actifs:
        try:
            whatsapp.envoyer_rappel_paiement(contrat)
            envoyes += 1
        except Exception:
            pass

    return jsonify({
        "message": f"Rappel envoyé pour {envoyes} contrat(s)",
        "contrats": envoyes,
    })
