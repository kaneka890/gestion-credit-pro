"""
Tests unitaires – Création de contrat et scoring
Lancer : pytest tests/ -v
"""
import pytest
from datetime import datetime, timedelta
from app import create_app, db
from app.config import Config


class TestConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    MONGODB_URI = "mongodb://localhost:27017/gcp_test"
    REDIS_URL = "redis://localhost:6379/1"
    JWT_SECRET_KEY = "test-secret"
    SECRET_KEY = "test-app-secret"


@pytest.fixture
def app():
    app = create_app(TestConfig)
    with app.app_context():
        db.create_all()
        yield app
        db.drop_all()


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def token_commercant(client):
    """Crée un commerçant et retourne son token JWT."""
    resp = client.post("/api/v1/auth/inscription", json={
        "nom_boutique": "Boutique Test",
        "nom_proprietaire": "Test Owner",
        "telephone": "+2250700000001",
        "password": "test1234",
        "wave_numero": "+2250700000001",
    })
    assert resp.status_code == 201
    return resp.get_json()["token"]


@pytest.fixture
def client_id(client, token_commercant):
    """Crée un client de test et retourne son ID."""
    resp = client.post(
        "/api/v1/clients",
        json={
            "nom_complet": "Kouassi Test",
            "telephone": "+2250700000010",
            "wave_numero": "+2250700000010",
        },
        headers={"Authorization": f"Bearer {token_commercant}"},
    )
    assert resp.status_code == 201
    return resp.get_json()["client"]["id"]


class TestAuth:
    def test_inscription_succes(self, client):
        resp = client.post("/api/v1/auth/inscription", json={
            "nom_boutique": "Ma Boutique",
            "nom_proprietaire": "Jean Dupont",
            "telephone": "+2250701234567",
            "password": "motdepasse123",
        })
        assert resp.status_code == 201
        data = resp.get_json()
        assert "token" in data
        assert data["commercant"]["telephone"] == "+2250701234567"

    def test_connexion_mauvais_mdp(self, client):
        client.post("/api/v1/auth/inscription", json={
            "nom_boutique": "Boutique", "nom_proprietaire": "Pierre",
            "telephone": "+2250701111111", "password": "correct"
        })
        resp = client.post("/api/v1/auth/connexion", json={
            "telephone": "+2250701111111",
            "password": "faux"
        })
        assert resp.status_code == 401

    def test_telephone_duplique(self, client, token_commercant):
        resp = client.post("/api/v1/auth/inscription", json={
            "nom_boutique": "Autre", "nom_proprietaire": "Autre",
            "telephone": "+2250700000001",  # Déjà utilisé
            "password": "test1234",
        })
        assert resp.status_code == 409


class TestClients:
    def test_creer_client(self, client, token_commercant):
        resp = client.post(
            "/api/v1/clients",
            json={"nom_complet": "Marie Coulibaly", "telephone": "+2250700000020"},
            headers={"Authorization": f"Bearer {token_commercant}"},
        )
        assert resp.status_code == 201
        data = resp.get_json()
        assert data["client"]["nom_complet"] == "Marie Coulibaly"
        assert "score_initial" in data

    def test_client_sans_auth(self, client):
        resp = client.post("/api/v1/clients", json={"nom_complet": "X", "telephone": "Y"})
        assert resp.status_code == 401


class TestContrats:
    def test_creer_contrat_succes(self, client, token_commercant, client_id):
        date_future = (datetime.utcnow() + timedelta(days=30)).isoformat()
        resp = client.post(
            "/api/v1/contrats",
            json={
                "client_id": client_id,
                "montant_initial": 5000,
                "date_echeance": date_future,
                "operateur_mm": "wave",
                "type_remboursement": "FLUX_QUOTIDIEN",
                "montant_flux_quotidien": 500,
                "description": "Sacs de riz",
            },
            headers={"Authorization": f"Bearer {token_commercant}"},
        )
        data = resp.get_json()
        # Score initial = 50 (neutre), plafond = 50*1000 = 50000 > 5000 → autorisé
        assert resp.status_code == 201
        assert data["contrat"]["montant_initial"] == 5000.0
        assert data["contrat"]["statut"] == "ACTIF"

    def test_contrat_date_passee(self, client, token_commercant, client_id):
        date_passee = (datetime.utcnow() - timedelta(days=1)).isoformat()
        resp = client.post(
            "/api/v1/contrats",
            json={
                "client_id": client_id,
                "montant_initial": 1000,
                "date_echeance": date_passee,
                "operateur_mm": "wave",
            },
            headers={"Authorization": f"Bearer {token_commercant}"},
        )
        assert resp.status_code == 400

    def test_contrat_client_inconnu(self, client, token_commercant):
        date_future = (datetime.utcnow() + timedelta(days=30)).isoformat()
        resp = client.post(
            "/api/v1/contrats",
            json={
                "client_id": "00000000-0000-0000-0000-000000000000",
                "montant_initial": 1000,
                "date_echeance": date_future,
                "operateur_mm": "wave",
            },
            headers={"Authorization": f"Bearer {token_commercant}"},
        )
        assert resp.status_code == 404


class TestScoring:
    def test_score_initial(self, client, token_commercant, client_id):
        resp = client.get(
            f"/api/v1/scores/client/{client_id}",
            headers={"Authorization": f"Bearer {token_commercant}"},
        )
        assert resp.status_code == 200
        data = resp.get_json()
        assert "passeport_confiance" in data
        score = data["passeport_confiance"]["score_global"]
        assert 0 <= score <= 100

    def test_eligibilite_montant_trop_eleve(self, client, token_commercant, client_id):
        resp = client.post(
            "/api/v1/scores/verifier-eligibilite",
            json={"client_id": client_id, "montant": 999999999},
            headers={"Authorization": f"Bearer {token_commercant}"},
        )
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["autorise"] is False
