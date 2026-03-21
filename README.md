# Gestion Crédit Pro – Backend v1.0 Alpha

Infrastructure financière pour le micro-crédit commerçant en Côte d'Ivoire.

## Démarrage rapide

### 1. Prérequis
- Python 3.12+
- Docker + Docker Compose (pour PostgreSQL, MongoDB, Redis)

### 2. Installation

```bash
cd gestion_credit_pro

# Copier la config
cp .env.example .env
# Éditer .env avec vos clés API (Wave, Orange, MTN, WhatsApp)

# Démarrer les bases de données
docker-compose up postgres mongodb redis -d

# Environnement Python
python -m venv venv
venv\Scripts\activate          # Windows
pip install -r requirements.txt

# Migrations base de données
flask db init
flask db migrate -m "init"
flask db upgrade

# Données de démonstration
flask seed-demo

# Lancer le serveur
python run.py
```

### 3. Lancer le Worker Celery (tâches asynchrones)

```bash
# Dans un second terminal
celery -A run.celery_app worker --loglevel=info
```

### 4. Tests

```bash
pytest tests/ -v
```

---

## Architecture

```
Flask API (Gateway)
    │
    ├─► PostgreSQL      Contrats, Clients, Scores (ACID)
    ├─► MongoDB         Flux de paiements (haute vélocité)
    ├─► Redis           File de tâches Celery
    └─► Celery Worker   Push Mobile Money, Rappels, Scoring
```

## Endpoints principaux

| Méthode | URL | Description |
|---------|-----|-------------|
| POST | /api/v1/auth/inscription | Nouveau commerçant |
| POST | /api/v1/auth/connexion | Login |
| POST | /api/v1/clients | Ajouter un client |
| POST | /api/v1/contrats | Créer un contrat (vérifie le score) |
| GET  | /api/v1/contrats/{id} | Détail + historique paiements |
| POST | /api/v1/contrats/{id}/push-paiement | Push Mobile Money manuel |
| POST | /api/v1/paiements/manuel | Paiement espèces |
| POST | /api/v1/paiements/webhook/wave | Callback Wave |
| POST | /api/v1/paiements/webhook/orange | Callback Orange Money |
| GET  | /api/v1/scores/client/{id} | Passeport de Confiance |
| POST | /api/v1/scores/verifier-eligibilite | Vérification avant crédit |

## Opérateurs Mobile Money supportés
- **Wave** CI
- **Orange Money** CI
- **MTN MoMo** CI
