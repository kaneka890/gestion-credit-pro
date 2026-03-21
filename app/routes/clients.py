from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.client import Client
from app.models.score import ScoreReputation
from app.services.scoring import ScoringService

clients_bp = Blueprint("clients", __name__)


@clients_bp.route("", methods=["POST"])
@jwt_required()
def creer_client():
    """Enregistrer un nouveau client."""
    commercant_id = get_jwt_identity()
    data = request.get_json()

    for champ in ["nom_complet", "telephone"]:
        if not data.get(champ):
            return jsonify({"erreur": f"Champ requis : {champ}"}), 400

    if Client.query.filter_by(telephone=data["telephone"]).first():
        return jsonify({"erreur": "Ce client existe déjà (même numéro)"}), 409

    client = Client(
        nom_complet=data["nom_complet"],
        telephone=data["telephone"],
        wave_numero=data.get("wave_numero"),
        orange_money_numero=data.get("orange_money_numero"),
        mtn_momo_numero=data.get("mtn_momo_numero"),
        quartier_residence=data.get("quartier_residence"),
        cni_numero=data.get("cni_numero"),
        garant_telephone=data.get("garant_telephone"),
        garant_nom=data.get("garant_nom"),
        commercant_id=commercant_id,
    )
    db.session.add(client)
    db.session.flush()  # Pour avoir l'ID avant commit

    # Créer un score initial
    score = ScoreReputation(client_id=client.id)
    score.recalculer()
    db.session.add(score)
    db.session.commit()

    return jsonify({
        "message": "Client enregistré",
        "client": client.to_dict(),
        "score_initial": score.to_dict(),
    }), 201


@clients_bp.route("", methods=["GET"])
@jwt_required()
def lister_clients():
    """Liste tous les clients du commerçant connecté."""
    commercant_id = get_jwt_identity()
    clients = Client.query.filter_by(
        commercant_id=commercant_id,
        est_actif=True
    ).order_by(Client.date_creation.desc()).all()

    return jsonify({
        "clients": [c.to_dict() for c in clients],
        "total": len(clients),
    })


@clients_bp.route("/<client_id>", methods=["GET"])
@jwt_required()
def detail_client(client_id):
    """Détail d'un client avec son score."""
    commercant_id = get_jwt_identity()
    client = Client.query.filter_by(
        id=client_id,
        commercant_id=commercant_id
    ).first()

    if not client:
        return jsonify({"erreur": "Client introuvable"}), 404

    score = ScoreReputation.query.filter_by(client_id=client_id).first()

    return jsonify({
        "client": client.to_dict(),
        "score": score.to_dict() if score else None,
    })


@clients_bp.route("/<client_id>/score/recalculer", methods=["POST"])
@jwt_required()
def recalculer_score(client_id):
    """Force le recalcul immédiat du score d'un client."""
    score = ScoringService().calculer_score_complet(client_id)
    return jsonify({"score": score.to_dict()})
