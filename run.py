"""
Point d'entrée principal – Gestion Crédit Pro v1.0 Alpha
Usage dev  : python run.py
Usage prod : gunicorn -w 4 -b 0.0.0.0:5000 "run:app"
"""
import os
from app import create_app, db

app = create_app()


@app.cli.command("init-db")
def init_db():
    """Crée toutes les tables en base. Lancer après 'flask db upgrade'."""
    with app.app_context():
        db.create_all()
        print("✓ Base de données initialisée")


@app.cli.command("seed-demo")
def seed_demo():
    """Insère des données de démonstration pour tester l'application."""
    from app.models.commercant import Commercant
    from app.models.client import Client
    from app.models.score import ScoreReputation
    from datetime import datetime, timedelta

    with app.app_context():
        # Commerçant démo
        comm = Commercant(
            nom_boutique="Épicerie Adjoua – Treichville",
            nom_proprietaire="Adjoua Konan",
            telephone="+2250700000001",
            quartier="Treichville",
            wave_numero="+2250700000001",
        )
        comm.set_password("demo1234")
        db.session.add(comm)
        db.session.flush()

        # Clients démo
        clients_data = [
            {"nom_complet": "Kouassi Brou", "telephone": "+2250700000010", "wave_numero": "+2250700000010", "garant_nom": "Chef Quartier Yao", "garant_telephone": "+2250700000099"},
            {"nom_complet": "Awa Traoré", "telephone": "+2250700000011", "orange_money_numero": "+2250700000011"},
            {"nom_complet": "Mamadou Diallo", "telephone": "+2250700000012", "mtn_momo_numero": "+2250700000012"},
        ]

        for cd in clients_data:
            client = Client(**cd, commercant_id=comm.id)
            db.session.add(client)
            db.session.flush()

            score = ScoreReputation(client_id=client.id)
            score.score_regularite = 80
            score.score_anciennete = 60
            score.score_recommandation = 100 if cd.get("garant_nom") else 0
            score.score_reactivite = 70
            score.recalculer()
            db.session.add(score)

        db.session.commit()
        print("✓ Données de démonstration insérées")
        print(f"  Commerçant : {comm.telephone} / demo1234")


if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
