from flask import Blueprint, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.models.client import Client
from app.models.score import ScoreReputation
from app.services.scoring import ScoringService

scores_bp = Blueprint("scores", __name__)


@scores_bp.route("/client/<client_id>", methods=["GET"])
@jwt_required()
def score_client(client_id):
    """
    Retourne le Passeport de Confiance d'un client.
    Tout commerçant peut consulter le score (avec permission du client à terme).
    """
    client = Client.query.get(client_id)
    if not client:
        return jsonify({"erreur": "Client introuvable"}), 404

    score = ScoreReputation.query.filter_by(client_id=client_id).first()
    if not score:
        score = ScoringService().calculer_score_complet(client_id)

    return jsonify({
        "client": client.to_dict(),
        "passeport_confiance": score.to_dict(),
        "recommandation": _libelle_score(score.score_global),
    })


@scores_bp.route("/verifier-eligibilite", methods=["POST"])
@jwt_required()
def verifier_eligibilite():
    """
    Vérifie si un client est éligible à un montant donné.
    Utilisé avant la création d'un contrat.
    """
    from flask import request
    data = request.get_json()
    client_id = data.get("client_id")
    montant = float(data.get("montant", 0))

    if not client_id or not montant:
        return jsonify({"erreur": "client_id et montant requis"}), 400

    decision = ScoringService().peut_obtenir_credit(client_id, montant)
    return jsonify(decision)


def _libelle_score(score: int) -> str:
    if score >= 80:
        return "Excellent – Crédit illimité dans le plafond"
    elif score >= 65:
        return "Bon – Crédit recommandé"
    elif score >= 50:
        return "Moyen – Crédit avec prudence"
    elif score >= 40:
        return "Risqué – Petit montant seulement"
    else:
        return "Bloqué – Historique de non-paiement"
