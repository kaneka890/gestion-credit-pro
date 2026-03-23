"""
Routes Paiements – Webhooks Mobile Money + Enregistrement manuel
"""
import hashlib
import hmac
from datetime import datetime
from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db, get_mongo_db
from app.models.contrat import ContratCredit, StatutContrat
from app.models.client import Client
from app.services.notifications import WhatsAppService

paiements_bp = Blueprint("paiements", __name__)


# ============================================================
# WEBHOOK WAVE – Reçoit les confirmations de paiement
# ============================================================
@paiements_bp.route("/webhook/wave", methods=["POST"])
def webhook_wave():
    """
    Wave appelle cette URL après qu'un client a confirmé son paiement.
    On met à jour le contrat et le solde dans MongoDB + PostgreSQL.
    """
    # Vérification signature HMAC Wave
    signature = request.headers.get("Wave-Signature", "")
    if not _verifier_signature_wave(request.data, signature):
        return jsonify({"erreur": "Signature invalide"}), 401

    event = request.get_json()
    if event.get("type") != "checkout.session.completed":
        return jsonify({"status": "ignored"}), 200

    session = event.get("data", {}).get("object", {})
    reference_interne = session.get("client_reference")
    montant = session.get("amount", 0) / 100  # Wave envoie en centimes
    reference_wave = session.get("id")

    return _enregistrer_paiement_confirme(
        reference_interne=reference_interne,
        montant=montant,
        operateur="wave",
        reference_operateur=reference_wave,
    )


# ============================================================
# WEBHOOK ORANGE MONEY
# ============================================================
@paiements_bp.route("/webhook/orange", methods=["POST"])
def webhook_orange():
    """Callback Orange Money après confirmation client."""
    data = request.get_json() or {}

    # Orange envoie status=SUCCESS quand c'est payé
    if data.get("status") != "SUCCESS":
        return jsonify({"status": "pending"}), 200

    return _enregistrer_paiement_confirme(
        reference_interne=data.get("order_id", ""),
        montant=float(data.get("amount", 0)),
        operateur="orange",
        reference_operateur=data.get("pay_token", ""),
    )


# ============================================================
# PAIEMENT MANUEL (Commerçant enregistre un paiement cash)
# ============================================================
@paiements_bp.route("/manuel", methods=["POST"])
@jwt_required()
def paiement_manuel():
    """
    Le commerçant enregistre un paiement reçu en espèces.
    Utile pour les zones sans Mobile Money.
    """
    commercant_id = get_jwt_identity()
    data = request.get_json()

    for champ in ["contrat_id", "montant"]:
        if not data.get(champ):
            return jsonify({"erreur": f"Champ requis : {champ}"}), 400

    contrat = ContratCredit.query.filter_by(
        id=data["contrat_id"],
        commercant_id=commercant_id
    ).first()
    if not contrat:
        return jsonify({"erreur": "Contrat introuvable"}), 404

    montant = float(data["montant"])
    if montant <= 0:
        return jsonify({"erreur": "Le montant doit être positif"}), 400

    import uuid
    reference = f"CASH_{str(uuid.uuid4())[:8].upper()}"

    return _enregistrer_paiement_confirme(
        reference_interne=str(contrat.id),
        montant=montant,
        operateur="cash",
        reference_operateur=reference,
        note=data.get("note", "Paiement espèces"),
    )


# ============================================================
# HELPER CENTRAL – Enregistre un paiement confirmé
# ============================================================
def _enregistrer_paiement_confirme(
    reference_interne: str,
    montant: float,
    operateur: str,
    reference_operateur: str,
    note: str = ""
):
    """
    Met à jour PostgreSQL + MongoDB après un paiement confirmé.
    Envoi du reçu WhatsApp au client.
    """
    contrat = ContratCredit.query.filter_by(id=reference_interne).first()
    if not contrat:
        current_app.logger.error(f"Webhook : contrat {reference_interne} introuvable")
        return jsonify({"status": "error", "message": "Contrat introuvable"}), 404

    # Mise à jour PostgreSQL (source of truth financière)
    montant_effectif = min(montant, float(contrat.montant_restant))
    contrat.montant_rembourse = float(contrat.montant_rembourse) + montant_effectif
    contrat.montant_restant = float(contrat.montant_restant) - montant_effectif

    if contrat.montant_restant <= 0:
        contrat.statut = StatutContrat.SOLDE
        contrat.date_solde = datetime.utcnow()
    elif contrat.statut == StatutContrat.EN_RETARD:
        contrat.statut = StatutContrat.ACTIF  # Réactivé après paiement

    # Enregistrer dans MongoDB (historique des flux)
    mongo = get_mongo_db()
    mongo.flux_paiements.update_one(
        {"contrat_id": str(contrat.id)},
        {
            "$push": {
                "transactions": {
                    "date": datetime.utcnow(),
                    "montant": montant_effectif,
                    "source": operateur,
                    "reference_api": reference_operateur,
                    "statut": "VALIDE",
                    "note": note,
                }
            },
            "$set": {"solde_restant": float(contrat.montant_restant)},
            "$setOnInsert": {"contrat_id": str(contrat.id), "client_id": str(contrat.client_id)},
        },
        upsert=True
    )

    db.session.commit()

    # Reçu WhatsApp
    client = Client.query.get(contrat.client_id)
    if client:
        WhatsAppService().envoyer_confirmation_paiement(
            telephone=client.telephone,
            nom_client=client.nom_complet,
            montant=montant_effectif,
            solde_restant=float(contrat.montant_restant),
            reference=reference_operateur,
        )
        # Recalcul score en arrière-plan
        from app.workers.payment_worker import recalculer_score_client
        recalculer_score_client.delay(str(client.id))

    return jsonify({
        "status": "success",
        "contrat_id": str(contrat.id),
        "montant_enregistre": montant_effectif,
        "solde_restant": float(contrat.montant_restant),
        "contrat_solde": contrat.statut == StatutContrat.SOLDE,
    })


def _verifier_signature_wave(payload: bytes, signature: str) -> bool:
    """Vérifie la signature HMAC-SHA256 envoyée par Wave."""
    secret = current_app.config.get("WAVE_API_KEY", "").encode()
    mac = hmac.new(secret, payload, hashlib.sha256).hexdigest()
    return hmac.compare_digest(mac, signature.replace("sha256=", ""))


# ============================================================
# HISTORIQUE GLOBAL – Tous les paiements du commerçant
# ============================================================
@paiements_bp.route("/historique", methods=["GET"])
@jwt_required()
def historique_paiements():
    """
    Retourne tous les paiements reçus pour tous les contrats du commerçant.
    Chaque transaction est enrichie avec le nom du client.
    Query params: limite (default 50), operateur (wave/orange/mtn/cash)
    """
    commercant_id = get_jwt_identity()
    limite = min(int(request.args.get("limite", 50)), 200)
    filtre_operateur = request.args.get("operateur")

    # 1. Récupérer tous les contrats du commerçant (PostgreSQL)
    contrats = ContratCredit.query.filter_by(commercant_id=commercant_id).all()
    if not contrats:
        return jsonify({"transactions": [], "total": 0, "total_montant": 0})

    contrat_map = {str(c.id): c for c in contrats}
    contrat_ids = list(contrat_map.keys())

    # Pré-charger les clients
    client_ids = list({str(c.client_id) for c in contrats})
    clients = {str(cl.id): cl for cl in Client.query.filter(Client.id.in_(client_ids)).all()}

    # 2. Récupérer les flux depuis MongoDB
    mongo = get_mongo_db()
    flux_cursor = mongo.flux_paiements.find({"contrat_id": {"$in": contrat_ids}})

    # 3. Aplatir et enrichir les transactions
    toutes_transactions = []
    for flux in flux_cursor:
        cid = flux.get("contrat_id", "")
        contrat = contrat_map.get(cid)
        if not contrat:
            continue
        client = clients.get(str(contrat.client_id))
        nom_client = client.nom_complet if client else "Client inconnu"
        telephone = client.telephone if client else ""

        for tx in flux.get("transactions", []):
            operateur = tx.get("source", "")
            if filtre_operateur and operateur != filtre_operateur:
                continue
            date_val = tx.get("date")
            if isinstance(date_val, datetime):
                date_str = date_val.isoformat()
            else:
                date_str = str(date_val) if date_val else ""

            toutes_transactions.append({
                "date": date_str,
                "montant": tx.get("montant", 0),
                "operateur": operateur,
                "reference": tx.get("reference_api", ""),
                "statut": tx.get("statut", "VALIDE"),
                "note": tx.get("note", ""),
                "contrat_id": cid,
                "client_nom": nom_client,
                "client_telephone": telephone,
                "montant_initial_contrat": float(contrat.montant_initial),
            })

    # 4. Trier par date décroissante et limiter
    toutes_transactions.sort(key=lambda t: t["date"], reverse=True)
    toutes_transactions = toutes_transactions[:limite]

    total_montant = sum(t["montant"] for t in toutes_transactions)

    return jsonify({
        "transactions": toutes_transactions,
        "total": len(toutes_transactions),
        "total_montant": total_montant,
    })
