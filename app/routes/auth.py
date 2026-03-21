from flask import Blueprint, request, jsonify
from flask_jwt_extended import create_access_token, jwt_required, get_jwt_identity
from app import db
from app.models.commercant import Commercant

auth_bp = Blueprint("auth", __name__)


@auth_bp.route("/inscription", methods=["POST"])
def inscription():
    """Inscription d'un nouveau commerçant."""
    data = request.get_json()

    champs_requis = ["nom_boutique", "nom_proprietaire", "telephone", "password"]
    for champ in champs_requis:
        if not data.get(champ):
            return jsonify({"erreur": f"Champ requis : {champ}"}), 400

    if Commercant.query.filter_by(telephone=data["telephone"]).first():
        return jsonify({"erreur": "Ce numéro est déjà enregistré"}), 409

    commercant = Commercant(
        nom_boutique=data["nom_boutique"],
        nom_proprietaire=data["nom_proprietaire"],
        telephone=data["telephone"],
        email=data.get("email"),
        quartier=data.get("quartier"),
        ville=data.get("ville", "Abidjan"),
        wave_numero=data.get("wave_numero"),
        orange_money_numero=data.get("orange_money_numero"),
        mtn_momo_numero=data.get("mtn_momo_numero"),
    )
    commercant.set_password(data["password"])

    db.session.add(commercant)
    db.session.commit()

    token = create_access_token(identity=str(commercant.id))
    return jsonify({
        "message": "Inscription réussie",
        "token": token,
        "commercant": commercant.to_dict(),
    }), 201


@auth_bp.route("/connexion", methods=["POST"])
def connexion():
    """Connexion d'un commerçant."""
    data = request.get_json()
    telephone = data.get("telephone")
    password = data.get("password")

    commercant = Commercant.query.filter_by(telephone=telephone).first()
    if not commercant or not commercant.check_password(password):
        return jsonify({"erreur": "Téléphone ou mot de passe incorrect"}), 401

    if not commercant.est_actif:
        return jsonify({"erreur": "Compte désactivé – contacter le support"}), 403

    token = create_access_token(identity=str(commercant.id))
    return jsonify({
        "token": token,
        "commercant": commercant.to_dict(),
    })


@auth_bp.route("/profil", methods=["GET"])
@jwt_required()
def profil():
    """Profil du commerçant connecté."""
    commercant_id = get_jwt_identity()
    commercant = Commercant.query.get(commercant_id)
    if not commercant:
        return jsonify({"erreur": "Commerçant introuvable"}), 404
    return jsonify(commercant.to_dict())
