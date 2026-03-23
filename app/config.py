import os
from dotenv import load_dotenv

load_dotenv()


class Config:
    # Base
    SECRET_KEY = os.getenv("SECRET_KEY", "dev-secret-key-insecure")
    JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY", "dev-jwt-secret")
    JWT_ACCESS_TOKEN_EXPIRES = 86400  # 24h en secondes

    # PostgreSQL
    SQLALCHEMY_DATABASE_URI = os.getenv(
        "DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/gestion_credit_pro"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {
        "pool_size": 10,
        "pool_recycle": 300,
        "pool_pre_ping": True,
    }

    # MongoDB (flux de paiements)
    MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://localhost:27017/gestion_credit_pro")

    # Redis + Celery (queue de tâches)
    REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    CELERY_BROKER_URL = REDIS_URL
    CELERY_RESULT_BACKEND = REDIS_URL
    CELERY_TASK_SERIALIZER = "json"
    CELERY_RESULT_SERIALIZER = "json"
    CELERY_ACCEPT_CONTENT = ["json"]
    CELERY_TIMEZONE = "Africa/Abidjan"

    # Mobile Money
    WAVE_API_BASE_URL = os.getenv("WAVE_API_BASE_URL", "https://api.wave.com/v1")
    WAVE_API_KEY = os.getenv("WAVE_API_KEY", "")
    WAVE_MERCHANT_ID = os.getenv("WAVE_MERCHANT_ID", "")

    ORANGE_MONEY_API_URL = os.getenv(
        "ORANGE_MONEY_API_URL",
        "https://api.orange.com/orange-money-webpay/ci/v1"
    )
    ORANGE_MONEY_CLIENT_ID = os.getenv("ORANGE_MONEY_CLIENT_ID", "")
    ORANGE_MONEY_CLIENT_SECRET = os.getenv("ORANGE_MONEY_CLIENT_SECRET", "")

    MTN_MOMO_API_URL = os.getenv("MTN_MOMO_API_URL", "https://sandbox.momodeveloper.mtn.com")
    MTN_SUBSCRIPTION_KEY = os.getenv("MTN_SUBSCRIPTION_KEY", "")
    MTN_API_USER = os.getenv("MTN_API_USER", "")
    MTN_API_KEY = os.getenv("MTN_API_KEY", "")

    # WhatsApp
    WHATSAPP_TOKEN = os.getenv("WHATSAPP_TOKEN", "")
    WHATSAPP_PHONE_ID = os.getenv("WHATSAPP_PHONE_ID", "")

    # Règles métier
    MAX_CREDIT_MONTANT = float(os.getenv("MAX_CREDIT_MONTANT", 500000))
    MIN_SCORE_POUR_CREDIT = int(os.getenv("MIN_SCORE_POUR_CREDIT", 40))


class DevelopmentConfig(Config):
    DEBUG = True


class ProductionConfig(Config):
    DEBUG = False
    SQLALCHEMY_ENGINE_OPTIONS = {
        "pool_size": 20,
        "max_overflow": 30,
        "pool_recycle": 300,
        "pool_pre_ping": True,
    }


config_map = {
    "development": DevelopmentConfig,
    "production": ProductionConfig,
    "default": DevelopmentConfig,
}

def get_config():
    env = os.getenv("FLASK_ENV", "development")
    return config_map.get(env, DevelopmentConfig)
