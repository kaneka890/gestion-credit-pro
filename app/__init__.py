from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_jwt_extended import JWTManager
from celery import Celery
from pymongo import MongoClient
import redis

from app.config import get_config

# Extensions globales (initialisées sans app, pattern Application Factory)
db = SQLAlchemy()
migrate = Migrate()
jwt = JWTManager()
celery_app = Celery()
mongo_client: MongoClient = None
redis_client: redis.Redis = None


def create_app(config_class=None):
    app = Flask(__name__)

    # Configuration
    cfg = config_class or get_config()
    app.config.from_object(cfg)

    # Init extensions SQL
    db.init_app(app)
    migrate.init_app(app, db)
    jwt.init_app(app)

    # Init MongoDB (optionnel — graceful degradation si URI absente)
    global mongo_client
    mongodb_uri = app.config.get("MONGODB_URI")
    if mongodb_uri and not mongodb_uri.startswith("mongodb://localhost"):
        try:
            mongo_client = MongoClient(mongodb_uri, serverSelectionTimeoutMS=3000)
        except Exception:
            mongo_client = None
    else:
        mongo_client = None

    # Init Redis
    global redis_client
    try:
        redis_client = redis.from_url(app.config["REDIS_URL"], decode_responses=True, socket_connect_timeout=3)
    except Exception:
        redis_client = None

    # Init Celery
    celery_app.conf.update(
        broker_url=app.config["CELERY_BROKER_URL"],
        result_backend=app.config["CELERY_RESULT_BACKEND"],
        task_serializer=app.config["CELERY_TASK_SERIALIZER"],
        timezone=app.config["CELERY_TIMEZONE"],
    )

    # Enregistrement des Blueprints (routes)
    from app.routes.auth import auth_bp
    from app.routes.contrats import contrats_bp
    from app.routes.paiements import paiements_bp
    from app.routes.scores import scores_bp
    from app.routes.clients import clients_bp
    from app.routes.rappels import rappels_bp

    app.register_blueprint(auth_bp, url_prefix="/api/v1/auth")
    app.register_blueprint(contrats_bp, url_prefix="/api/v1/contrats")
    app.register_blueprint(paiements_bp, url_prefix="/api/v1/paiements")
    app.register_blueprint(scores_bp, url_prefix="/api/v1/scores")
    app.register_blueprint(clients_bp, url_prefix="/api/v1/clients")
    app.register_blueprint(rappels_bp, url_prefix="/api/v1/rappels")

    # Health check
    @app.route("/health")
    def health():
        return {"status": "ok", "version": "1.0.0-alpha", "app": "Gestion Crédit Pro"}

    # ── Flutter Web App ──────────────────────────────────────
    import os
    from flask import send_from_directory

    flutter_dir = os.path.join(os.path.dirname(app.root_path), "static_flutter")

    @app.route("/", defaults={"path": ""})
    @app.route("/<path:path>")
    def servir_flutter(path):
        """Sert l'application Flutter Web depuis static_flutter/."""
        # Ne pas intercepter les routes API
        if path.startswith("api/"):
            from flask import abort
            abort(404)
        fichier = os.path.join(flutter_dir, path)
        if path and os.path.isfile(fichier):
            return send_from_directory(flutter_dir, path)
        return send_from_directory(flutter_dir, "index.html")

    return app


def get_mongo_db():
    """Retourne la base MongoDB active."""
    return mongo_client["gestion_credit_pro"]
