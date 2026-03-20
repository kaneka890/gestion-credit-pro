"""
Serveur de développement autonome – Gestion Crédit Pro
Utilise SQLite (pas besoin de PostgreSQL/MongoDB/Redis)
Lance avec : python run_dev.py
"""
import uuid
import json
import hashlib
import hmac
from datetime import datetime, timedelta, timezone
from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_jwt_extended import (
    JWTManager, create_access_token,
    jwt_required, get_jwt_identity
)
from werkzeug.security import generate_password_hash, check_password_hash

import os
app = Flask(__name__, static_folder='static_flutter', static_url_path='')

@app.after_request
def ajouter_cors(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
    response.headers["Access-Control-Allow-Private-Network"] = "true"
    return response

@app.before_request
def gerer_preflight():
    from flask import request as req
    if req.method == "OPTIONS":
        from flask import make_response
        resp = make_response()
        resp.headers["Access-Control-Allow-Origin"] = "*"
        resp.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
        resp.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
        resp.headers["Access-Control-Allow-Private-Network"] = "true"
        resp.status_code = 200
        return resp

# Config – SQLite local ou PostgreSQL Railway
DATABASE_URL = os.environ.get('DATABASE_URL', 'sqlite:///gestion_credit_dev.db')
# Railway fournit postgres:// mais SQLAlchemy veut postgresql://
if DATABASE_URL.startswith('postgres://'):
    DATABASE_URL = DATABASE_URL.replace('postgres://', 'postgresql://', 1)

app.config['SQLALCHEMY_DATABASE_URI'] = DATABASE_URL
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['JWT_SECRET_KEY'] = os.environ.get('JWT_SECRET_KEY', 'dev-secret-key-gestion-credit-pro')
app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(hours=24)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'dev-app-secret')

db = SQLAlchemy(app)
jwt = JWTManager(app)

# ═══════════════════════════════════════════════════════
# MODÈLES
# ═══════════════════════════════════════════════════════

class Commercant(db.Model):
    __tablename__ = 'commercants'
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    nom_boutique = db.Column(db.String(200), nullable=False)
    nom_proprietaire = db.Column(db.String(200), nullable=False)
    telephone = db.Column(db.String(20), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=True)
    quartier = db.Column(db.String(100))
    ville = db.Column(db.String(100), default='Abidjan')
    password_hash = db.Column(db.String(255), nullable=False)
    wave_numero = db.Column(db.String(20))
    orange_money_numero = db.Column(db.String(20))
    mtn_momo_numero = db.Column(db.String(20))
    est_actif = db.Column(db.Boolean, default=True)
    date_inscription = db.Column(db.DateTime, default=datetime.utcnow)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

    def to_dict(self):
        return {
            'id': self.id,
            'nom_boutique': self.nom_boutique,
            'nom_proprietaire': self.nom_proprietaire,
            'telephone': self.telephone,
            'quartier': self.quartier,
            'ville': self.ville,
            'date_inscription': self.date_inscription.isoformat(),
        }


class Client(db.Model):
    __tablename__ = 'clients'
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    nom_complet = db.Column(db.String(200), nullable=False)
    telephone = db.Column(db.String(20), unique=True, nullable=False)
    wave_numero = db.Column(db.String(20))
    orange_money_numero = db.Column(db.String(20))
    mtn_momo_numero = db.Column(db.String(20))
    quartier_residence = db.Column(db.String(100))
    garant_telephone = db.Column(db.String(20))
    garant_nom = db.Column(db.String(200))
    commercant_id = db.Column(db.String(36), db.ForeignKey('commercants.id'), nullable=False)
    date_creation = db.Column(db.DateTime, default=datetime.utcnow)
    est_actif = db.Column(db.Boolean, default=True)

    def get_numero_mobile_money(self, operateur):
        return {'wave': self.wave_numero, 'orange': self.orange_money_numero, 'mtn': self.mtn_momo_numero}.get(operateur)

    def to_dict(self):
        return {
            'id': self.id,
            'nom_complet': self.nom_complet,
            'telephone': self.telephone,
            'quartier_residence': self.quartier_residence,
            'a_garant': bool(self.garant_telephone),
            'date_creation': self.date_creation.isoformat(),
        }


class ContratCredit(db.Model):
    __tablename__ = 'contrats_credit'
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    commercant_id = db.Column(db.String(36), db.ForeignKey('commercants.id'), nullable=False)
    client_id = db.Column(db.String(36), db.ForeignKey('clients.id'), nullable=False)
    montant_initial = db.Column(db.Float, nullable=False)
    montant_rembourse = db.Column(db.Float, default=0.0)
    montant_restant = db.Column(db.Float, nullable=False)
    taux_service = db.Column(db.Float, default=0.0)
    type_remboursement = db.Column(db.String(30), default='FLUX_QUOTIDIEN')
    montant_flux_quotidien = db.Column(db.Float)
    date_creation = db.Column(db.DateTime, default=datetime.utcnow)
    date_echeance = db.Column(db.DateTime, nullable=False)
    date_solde = db.Column(db.DateTime)
    statut = db.Column(db.String(20), default='ACTIF')
    operateur_mm = db.Column(db.String(20))
    description = db.Column(db.String(500))
    score_au_moment_octroi = db.Column(db.Integer)
    # Paiements stockés en JSON (remplace MongoDB)
    _transactions_json = db.Column(db.Text, default='[]')

    @property
    def transactions(self):
        return json.loads(self._transactions_json or '[]')

    def ajouter_transaction(self, tx):
        liste = self.transactions
        liste.append(tx)
        self._transactions_json = json.dumps(liste, default=str)

    def pourcentage_rembourse(self):
        if self.montant_initial == 0:
            return 0.0
        return round(self.montant_rembourse / self.montant_initial * 100, 1)

    def to_dict(self):
        return {
            'id': self.id,
            'commercant_id': self.commercant_id,
            'client_id': self.client_id,
            'montant_initial': self.montant_initial,
            'montant_rembourse': self.montant_rembourse,
            'montant_restant': self.montant_restant,
            'taux_service': self.taux_service,
            'type_remboursement': self.type_remboursement,
            'montant_flux_quotidien': self.montant_flux_quotidien,
            'statut': self.statut,
            'operateur_mm': self.operateur_mm or '',
            'description': self.description,
            'date_creation': self.date_creation.isoformat(),
            'date_echeance': self.date_echeance.isoformat(),
            'pourcentage_rembourse': self.pourcentage_rembourse(),
            'score_au_moment_octroi': self.score_au_moment_octroi,
        }


class ScoreReputation(db.Model):
    __tablename__ = 'scores_reputation'
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    client_id = db.Column(db.String(36), db.ForeignKey('clients.id'), unique=True, nullable=False)
    score_global = db.Column(db.Integer, default=50)
    score_regularite = db.Column(db.Integer, default=50)
    score_anciennete = db.Column(db.Integer, default=50)
    score_recommandation = db.Column(db.Integer, default=0)
    score_reactivite = db.Column(db.Integer, default=50)
    niveau_risque = db.Column(db.String(20), default='MOYEN')
    plafond_credit_autorise = db.Column(db.Float, default=50000.0)
    total_contrats = db.Column(db.Integer, default=0)
    contrats_soldes_a_temps = db.Column(db.Integer, default=0)
    contrats_en_retard = db.Column(db.Integer, default=0)
    jours_relation_commerciale = db.Column(db.Integer, default=0)
    date_calcul = db.Column(db.DateTime, default=datetime.utcnow)

    def recalculer(self):
        r = self.score_regularite or 50
        a = self.score_anciennete or 50
        rec = self.score_recommandation or 0
        re = self.score_reactivite or 50
        self.score_global = int(r * 0.40 + a * 0.20 + rec * 0.15 + re * 0.25)
        if self.score_global >= 75:
            self.niveau_risque = 'FAIBLE'
            self.plafond_credit_autorise = min(5000000, self.score_global * 30000)
        elif self.score_global >= 55:
            self.niveau_risque = 'MOYEN'
            self.plafond_credit_autorise = min(1500000, self.score_global * 15000)
        elif self.score_global >= 40:
            self.niveau_risque = 'ELEVE'
            self.plafond_credit_autorise = min(300000, self.score_global * 5000)
        else:
            self.niveau_risque = 'BLOQUE'
            self.plafond_credit_autorise = 0
        self.date_calcul = datetime.utcnow()

    def to_dict(self):
        return {
            'client_id': self.client_id,
            'score_global': self.score_global,
            'composantes': {
                'regularite': {'score': self.score_regularite, 'poids': '40%'},
                'anciennete': {'score': self.score_anciennete, 'poids': '20%'},
                'recommandation': {'score': self.score_recommandation, 'poids': '15%'},
                'reactivite': {'score': self.score_reactivite, 'poids': '25%'},
            },
            'niveau_risque': self.niveau_risque,
            'plafond_credit_autorise': self.plafond_credit_autorise,
            'statistiques': {
                'total_contrats': self.total_contrats,
                'soldes_a_temps': self.contrats_soldes_a_temps,
                'en_retard': self.contrats_en_retard,
                'jours_relation': self.jours_relation_commerciale,
            },
            'date_calcul': self.date_calcul.isoformat(),
        }


# ═══════════════════════════════════════════════════════
# ROUTES – AUTH
# ═══════════════════════════════════════════════════════

@app.route('/api/v1/auth/inscription', methods=['POST'])
def inscription():
    data = request.get_json()
    for champ in ['nom_boutique', 'nom_proprietaire', 'telephone', 'password']:
        if not data.get(champ):
            return jsonify({'erreur': f'Champ requis : {champ}'}), 400

    if Commercant.query.filter_by(telephone=data['telephone']).first():
        return jsonify({'erreur': 'Ce numéro est déjà enregistré'}), 409

    c = Commercant(
        nom_boutique=data['nom_boutique'],
        nom_proprietaire=data['nom_proprietaire'],
        telephone=data['telephone'],
        email=data.get('email'),
        quartier=data.get('quartier'),
        ville=data.get('ville', 'Abidjan'),
        wave_numero=data.get('wave_numero'),
        orange_money_numero=data.get('orange_money_numero'),
        mtn_momo_numero=data.get('mtn_momo_numero'),
    )
    c.set_password(data['password'])
    db.session.add(c)
    db.session.commit()
    token = create_access_token(identity=c.id)
    return jsonify({'message': 'Inscription réussie', 'token': token, 'commercant': c.to_dict()}), 201


@app.route('/api/v1/auth/connexion', methods=['POST'])
def connexion():
    data = request.get_json()
    c = Commercant.query.filter_by(telephone=data.get('telephone')).first()
    if not c or not c.check_password(data.get('password', '')):
        return jsonify({'erreur': 'Téléphone ou mot de passe incorrect'}), 401
    token = create_access_token(identity=c.id)
    return jsonify({'token': token, 'commercant': c.to_dict()})


@app.route('/api/v1/auth/profil', methods=['GET'])
@jwt_required()
def profil():
    c = Commercant.query.get(get_jwt_identity())
    return jsonify(c.to_dict()) if c else (jsonify({'erreur': 'Introuvable'}), 404)


# ═══════════════════════════════════════════════════════
# ROUTES – CLIENTS
# ═══════════════════════════════════════════════════════

@app.route('/api/v1/clients', methods=['POST'])
@jwt_required()
def creer_client():
    commercant_id = get_jwt_identity()
    data = request.get_json()
    for champ in ['nom_complet', 'telephone']:
        if not data.get(champ):
            return jsonify({'erreur': f'Champ requis : {champ}'}), 400
    if Client.query.filter_by(telephone=data['telephone']).first():
        return jsonify({'erreur': 'Ce client existe déjà'}), 409

    client = Client(
        nom_complet=data['nom_complet'],
        telephone=data['telephone'],
        wave_numero=data.get('wave_numero'),
        orange_money_numero=data.get('orange_money_numero'),
        mtn_momo_numero=data.get('mtn_momo_numero'),
        quartier_residence=data.get('quartier_residence'),
        garant_telephone=data.get('garant_telephone'),
        garant_nom=data.get('garant_nom'),
        commercant_id=commercant_id,
    )
    db.session.add(client)
    db.session.flush()

    score = ScoreReputation(client_id=client.id)
    score.score_recommandation = 100 if data.get('garant_telephone') else 0
    score.recalculer()
    db.session.add(score)
    db.session.commit()
    return jsonify({'message': 'Client enregistré', 'client': client.to_dict(), 'score_initial': score.to_dict()}), 201


@app.route('/api/v1/clients', methods=['GET'])
@jwt_required()
def lister_clients():
    commercant_id = get_jwt_identity()
    clients = Client.query.filter_by(commercant_id=commercant_id, est_actif=True).all()
    return jsonify({'clients': [c.to_dict() for c in clients], 'total': len(clients)})


@app.route('/api/v1/clients/<client_id>', methods=['GET'])
@jwt_required()
def detail_client(client_id):
    client = Client.query.get(client_id)
    if not client:
        return jsonify({'erreur': 'Client introuvable'}), 404
    score = ScoreReputation.query.filter_by(client_id=client_id).first()
    return jsonify({'client': client.to_dict(), 'score': score.to_dict() if score else None})


@app.route('/api/v1/clients/<client_id>', methods=['PUT'])
@jwt_required()
def modifier_client(client_id):
    commercant_id = get_jwt_identity()
    client = Client.query.filter_by(id=client_id, commercant_id=commercant_id).first()
    if not client:
        return jsonify({'erreur': 'Client introuvable'}), 404
    data = request.get_json() or {}
    champs_modifiables = [
        'nom_complet', 'telephone', 'quartier_residence',
        'wave_numero', 'orange_money_numero', 'mtn_momo_numero',
        'garant_nom', 'garant_telephone',
    ]
    for champ in champs_modifiables:
        if champ in data:
            setattr(client, champ, data[champ] or None)
    # Recalcul score si garant modifié
    score = ScoreReputation.query.filter_by(client_id=client_id).first()
    if score and 'garant_nom' in data:
        score.recalculer()
    db.session.commit()
    return jsonify({'message': 'Client mis à jour', 'client': client.to_dict()})


# ═══════════════════════════════════════════════════════
# ROUTES – CONTRATS
# ═══════════════════════════════════════════════════════

@app.route('/api/v1/contrats', methods=['POST'])
@jwt_required()
def creer_contrat():
    commercant_id = get_jwt_identity()
    data = request.get_json()
    for champ in ['client_id', 'montant_initial', 'date_echeance', 'operateur_mm']:
        if not data.get(champ):
            return jsonify({'erreur': f'Champ requis : {champ}'}), 400

    montant = float(data['montant_initial'])
    client = Client.query.filter_by(id=data['client_id'], commercant_id=commercant_id).first()
    if not client:
        return jsonify({'erreur': 'Client introuvable'}), 404

    # Vérification score
    score = ScoreReputation.query.filter_by(client_id=data['client_id']).first()
    if not score:
        score = ScoreReputation(client_id=data['client_id'])
        score.recalculer()
        db.session.add(score)
        db.session.commit()

    if score.niveau_risque == 'BLOQUE':
        return jsonify({'erreur': 'Crédit refusé', 'raison': 'Score insuffisant', 'score': score.score_global}), 403
    if montant > score.plafond_credit_autorise:
        return jsonify({'erreur': 'Crédit refusé', 'raison': f'Dépasse le plafond de {score.plafond_credit_autorise:.0f} FCFA', 'score': score.score_global}), 403

    try:
        date_echeance = datetime.fromisoformat(data['date_echeance'])
    except ValueError:
        return jsonify({'erreur': 'Format date invalide'}), 400

    if date_echeance <= datetime.utcnow():
        return jsonify({'erreur': 'La date doit être dans le futur'}), 400

    contrat = ContratCredit(
        commercant_id=commercant_id,
        client_id=data['client_id'],
        montant_initial=montant,
        montant_restant=montant,
        taux_service=float(data.get('taux_service', 0.0)),
        type_remboursement=data.get('type_remboursement', 'FLUX_QUOTIDIEN'),
        montant_flux_quotidien=float(data['montant_flux_quotidien']) if data.get('montant_flux_quotidien') else None,
        date_echeance=date_echeance,
        operateur_mm=data['operateur_mm'].lower(),
        description=data.get('description', ''),
        score_au_moment_octroi=score.score_global,
    )
    db.session.add(contrat)

    # Mise à jour score
    score.total_contrats += 1
    jours = (datetime.utcnow() - client.date_creation).days
    score.score_anciennete = min(100, jours)
    score.recalculer()
    db.session.commit()

    return jsonify({
        'message': 'Contrat créé',
        'contrat': contrat.to_dict(),
        'decision_credit': {'autorise': True, 'score': score.score_global, 'raison': f'Score {score.score_global}/100'},
    }), 201


@app.route('/api/v1/contrats', methods=['GET'])
@jwt_required()
def lister_contrats():
    commercant_id = get_jwt_identity()
    statut = request.args.get('statut')
    client_id = request.args.get('client_id')
    query = ContratCredit.query.filter_by(commercant_id=commercant_id)
    if statut:
        query = query.filter_by(statut=statut.upper())
    if client_id:
        query = query.filter_by(client_id=client_id)
    contrats = query.order_by(ContratCredit.date_creation.desc()).all()
    return jsonify({'contrats': [c.to_dict() for c in contrats], 'total': len(contrats)})


@app.route('/api/v1/contrats/<contrat_id>', methods=['GET'])
@jwt_required()
def detail_contrat(contrat_id):
    commercant_id = get_jwt_identity()
    contrat = ContratCredit.query.filter_by(id=contrat_id, commercant_id=commercant_id).first()
    if not contrat:
        return jsonify({'erreur': 'Contrat introuvable'}), 404
    return jsonify({
        'contrat': contrat.to_dict(),
        'historique_paiements': contrat.transactions,
        'nb_transactions': len(contrat.transactions),
    })


@app.route('/api/v1/contrats/<contrat_id>/marquer-solde', methods=['PATCH'])
@jwt_required()
def marquer_solde(contrat_id):
    contrat = ContratCredit.query.filter_by(id=contrat_id, commercant_id=get_jwt_identity()).first()
    if not contrat:
        return jsonify({'erreur': 'Introuvable'}), 404
    contrat.statut = 'SOLDE'
    contrat.date_solde = datetime.utcnow()
    contrat.montant_rembourse = contrat.montant_initial
    contrat.montant_restant = 0
    db.session.commit()
    return jsonify({'message': 'Soldé', 'contrat': contrat.to_dict()})


@app.route('/api/v1/contrats/<contrat_id>/push-paiement', methods=['POST'])
@jwt_required()
def push_paiement(contrat_id):
    contrat = ContratCredit.query.filter_by(id=contrat_id, commercant_id=get_jwt_identity()).first()
    if not contrat:
        return jsonify({'erreur': 'Introuvable'}), 404
    montant = float(request.get_json().get('montant', contrat.montant_flux_quotidien or contrat.montant_restant))
    return jsonify({
        'message': f'Push {contrat.operateur_mm.upper()} simulé – {montant:.0f} FCFA',
        'task_id': str(uuid.uuid4()),
        'operateur': contrat.operateur_mm,
        'montant': montant,
    })


# ═══════════════════════════════════════════════════════
# ROUTES – PAIEMENTS
# ═══════════════════════════════════════════════════════

@app.route('/api/v1/paiements/manuel', methods=['POST'])
@jwt_required()
def paiement_manuel():
    commercant_id = get_jwt_identity()
    data = request.get_json()
    contrat = ContratCredit.query.filter_by(id=data.get('contrat_id'), commercant_id=commercant_id).first()
    if not contrat:
        return jsonify({'erreur': 'Contrat introuvable'}), 404

    montant = float(data['montant'])
    montant_effectif = min(montant, contrat.montant_restant)
    contrat.montant_rembourse += montant_effectif
    contrat.montant_restant -= montant_effectif

    if contrat.montant_restant <= 0:
        contrat.statut = 'SOLDE'
        contrat.date_solde = datetime.utcnow()
    elif contrat.statut == 'EN_RETARD':
        contrat.statut = 'ACTIF'

    ref = f"CASH_{str(uuid.uuid4())[:8].upper()}"
    contrat.ajouter_transaction({
        'date': datetime.utcnow().isoformat(),
        'montant': montant_effectif,
        'source': 'cash',
        'reference_api': ref,
        'statut': 'VALIDE',
        'note': data.get('note', 'Paiement espèces'),
    })
    db.session.commit()
    return jsonify({
        'status': 'success',
        'montant_enregistre': montant_effectif,
        'solde_restant': contrat.montant_restant,
        'contrat_solde': contrat.statut == 'SOLDE',
    })


# ═══════════════════════════════════════════════════════
# ROUTES – SCORES
# ═══════════════════════════════════════════════════════

@app.route('/api/v1/scores/client/<client_id>', methods=['GET'])
@jwt_required()
def score_client(client_id):
    client = Client.query.get(client_id)
    if not client:
        return jsonify({'erreur': 'Client introuvable'}), 404
    score = ScoreReputation.query.filter_by(client_id=client_id).first()
    if not score:
        score = ScoreReputation(client_id=client_id)
        score.recalculer()
        db.session.add(score)
        db.session.commit()

    recommandation_map = {
        'FAIBLE': 'Excellent – Crédit autorisé jusqu\'au plafond',
        'MOYEN': 'Bon – Crédit recommandé avec prudence',
        'ELEVE': 'Risqué – Petit montant seulement',
        'BLOQUE': 'Bloqué – Historique de non-paiement',
    }
    return jsonify({
        'client': client.to_dict(),
        'passeport_confiance': score.to_dict(),
        'recommandation': recommandation_map.get(score.niveau_risque, ''),
    })


@app.route('/api/v1/scores/verifier-eligibilite', methods=['POST'])
@jwt_required()
def verifier_eligibilite():
    data = request.get_json()
    client_id = data.get('client_id')
    montant = float(data.get('montant', 0))
    if not client_id or not montant:
        return jsonify({'erreur': 'client_id et montant requis'}), 400

    score = ScoreReputation.query.filter_by(client_id=client_id).first()
    if not score:
        score = ScoreReputation(client_id=client_id)
        score.recalculer()
        db.session.add(score)
        db.session.commit()

    if score.niveau_risque == 'BLOQUE':
        return jsonify({'autorise': False, 'raison': 'Score insuffisant', 'score': score.score_global, 'plafond': 0})
    if montant > score.plafond_credit_autorise:
        return jsonify({'autorise': False, 'raison': f'Dépasse le plafond ({score.plafond_credit_autorise:.0f} FCFA)', 'score': score.score_global, 'plafond': score.plafond_credit_autorise})

    contrat_retard = ContratCredit.query.filter_by(client_id=client_id, statut='EN_RETARD').first()
    if contrat_retard:
        return jsonify({'autorise': False, 'raison': 'Contrat en retard non soldé', 'score': score.score_global, 'plafond': 0})

    return jsonify({'autorise': True, 'raison': f'Score {score.score_global}/100 – risque {score.niveau_risque}', 'score': score.score_global, 'plafond': score.plafond_credit_autorise})


# ═══════════════════════════════════════════════════════
# HEALTH CHECK + DÉMARRAGE
# ═══════════════════════════════════════════════════════

@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def servir_flutter(path):
    fichier = os.path.join(app.static_folder, path)
    if path and os.path.exists(fichier):
        return app.send_static_file(path)
    return app.send_static_file('index.html')

@app.route('/health')
def health():
    return jsonify({'status': 'ok', 'version': '1.0.0-alpha-dev', 'app': 'Gestion Crédit Pro'})


if __name__ == '__main__':
    with app.app_context():
        db.create_all()
        print('[OK] Base de donnees prete')
        port = int(os.environ.get('PORT', 5000))
        print(f'[OK] Serveur sur http://localhost:{port}')
        print('-' * 40)
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=False)
