"""
Service Mobile Money – Côte d'Ivoire
Gère les appels aux APIs Wave, Orange Money et MTN MoMo.

Architecture : chaque méthode retourne un dict standardisé :
{
    "succes": bool,
    "reference": str,       # Référence unique de la transaction chez l'opérateur
    "message": str,
    "donnees_brutes": dict  # Réponse brute de l'API (pour audit)
}
"""
import uuid
import requests
from flask import current_app


class ResultatTransaction:
    def __init__(self, succes: bool, reference: str, message: str, donnees_brutes: dict = None):
        self.succes = succes
        self.reference = reference
        self.message = message
        self.donnees_brutes = donnees_brutes or {}

    def to_dict(self):
        return {
            "succes": self.succes,
            "reference": self.reference,
            "message": self.message,
            "donnees_brutes": self.donnees_brutes,
        }


# ============================================================
# WAVE CI
# ============================================================
class WaveService:
    """
    Intégration Wave Côte d'Ivoire.
    Doc officielle : https://docs.wave.com/
    """

    def __init__(self):
        self.base_url = current_app.config["WAVE_API_BASE_URL"]
        self.api_key = current_app.config["WAVE_API_KEY"]
        self.merchant_id = current_app.config["WAVE_MERCHANT_ID"]

    def _headers(self):
        return {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

    def envoyer_demande_paiement(
        self,
        telephone_client: str,
        montant: float,
        reference_interne: str,
        description: str = "Remboursement crédit"
    ) -> ResultatTransaction:
        """
        Envoie un Push de paiement au client Wave.
        Le client reçoit une notification et doit confirmer sur son app.
        """
        payload = {
            "currency": "XOF",
            "amount": int(montant),  # Wave accepte des entiers (FCFA)
            "merchant_id": self.merchant_id,
            "client_reference": reference_interne,
            "customer_phone": telephone_client,
            "description": description,
            "callback_url": f"{self._get_base_url()}/api/v1/paiements/webhook/wave",
        }

        try:
            response = requests.post(
                f"{self.base_url}/checkout/sessions",
                json=payload,
                headers=self._headers(),
                timeout=15
            )
            data = response.json()

            if response.status_code in (200, 201) and data.get("id"):
                return ResultatTransaction(
                    succes=True,
                    reference=data["id"],
                    message="Demande Wave envoyée – en attente confirmation client",
                    donnees_brutes=data,
                )

            return ResultatTransaction(
                succes=False,
                reference="",
                message=data.get("message", "Erreur Wave inconnue"),
                donnees_brutes=data,
            )

        except requests.exceptions.Timeout:
            return ResultatTransaction(False, "", "Timeout Wave API – réessayer dans 30s")
        except requests.exceptions.ConnectionError:
            return ResultatTransaction(False, "", "Réseau indisponible – transaction en file d'attente")

    def verifier_statut(self, reference_wave: str) -> ResultatTransaction:
        """Vérifie si un paiement Wave a été confirmé."""
        try:
            response = requests.get(
                f"{self.base_url}/checkout/sessions/{reference_wave}",
                headers=self._headers(),
                timeout=10
            )
            data = response.json()
            est_paye = data.get("payment_status") == "succeeded"

            return ResultatTransaction(
                succes=est_paye,
                reference=reference_wave,
                message="Payé" if est_paye else f"Statut: {data.get('payment_status')}",
                donnees_brutes=data,
            )
        except Exception as e:
            return ResultatTransaction(False, reference_wave, str(e))

    def _get_base_url(self):
        return current_app.config.get("APP_BASE_URL", "https://votre-domaine.com")


# ============================================================
# ORANGE MONEY CI
# ============================================================
class OrangeMoneyService:
    """
    Intégration Orange Money Côte d'Ivoire (Web Pay API).
    """

    def __init__(self):
        self.base_url = current_app.config["ORANGE_MONEY_API_URL"]
        self.client_id = current_app.config["ORANGE_MONEY_CLIENT_ID"]
        self.client_secret = current_app.config["ORANGE_MONEY_CLIENT_SECRET"]
        self._token = None

    def _obtenir_token(self) -> str:
        """OAuth2 – récupère le token d'accès."""
        if self._token:
            return self._token

        response = requests.post(
            "https://api.orange.com/oauth/v3/token",
            data={"grant_type": "client_credentials"},
            auth=(self.client_id, self.client_secret),
            timeout=10
        )
        data = response.json()
        self._token = data.get("access_token", "")
        return self._token

    def envoyer_demande_paiement(
        self,
        telephone_client: str,
        montant: float,
        reference_interne: str,
        description: str = "Remboursement crédit"
    ) -> ResultatTransaction:
        """
        Initie une transaction Orange Money (USSD Push).
        Le client reçoit *#144# et doit valider avec son PIN.
        """
        numero_normalize = telephone_client.replace("+", "").replace(" ", "")
        order_id = reference_interne[:36]

        payload = {
            "merchant_key": current_app.config.get("ORANGE_MONEY_MERCHANT_KEY", ""),
            "currency": "OUV",  # Code devise Orange Money CI
            "order_id": order_id,
            "amount": int(montant),
            "return_url": f"{self._get_base_url()}/api/v1/paiements/webhook/orange",
            "cancel_url": f"{self._get_base_url()}/api/v1/paiements/annule",
            "notif_url": f"{self._get_base_url()}/api/v1/paiements/webhook/orange",
            "lang": "fr",
            "reference": description,
            "customer_phone": numero_normalize,
        }

        try:
            token = self._obtenir_token()
            response = requests.post(
                f"{self.base_url}/webpayment",
                json=payload,
                headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
                timeout=15
            )
            data = response.json()

            if response.status_code == 200 and data.get("status") == "SUCCESS":
                return ResultatTransaction(
                    succes=True,
                    reference=data.get("pay_token", order_id),
                    message="Push Orange Money envoyé – client doit valider *#144#",
                    donnees_brutes=data,
                )

            return ResultatTransaction(
                succes=False,
                reference="",
                message=data.get("message", "Erreur Orange Money"),
                donnees_brutes=data,
            )

        except requests.exceptions.Timeout:
            return ResultatTransaction(False, "", "Timeout Orange Money")
        except Exception as e:
            return ResultatTransaction(False, "", str(e))

    def _get_base_url(self):
        return current_app.config.get("APP_BASE_URL", "https://votre-domaine.com")


# ============================================================
# MTN MoMo CI
# ============================================================
class MTNMoMoService:
    """Intégration MTN Mobile Money (API MoMo Collections)."""

    def __init__(self):
        self.base_url = current_app.config["MTN_MOMO_API_URL"]
        self.subscription_key = current_app.config["MTN_SUBSCRIPTION_KEY"]

    def envoyer_demande_paiement(
        self,
        telephone_client: str,
        montant: float,
        reference_interne: str,
        description: str = "Remboursement crédit"
    ) -> ResultatTransaction:
        """Initie une demande de collecte MTN MoMo."""
        reference_uuid = str(uuid.uuid4())
        numero_normalize = telephone_client.replace("+", "").replace(" ", "")

        payload = {
            "amount": str(int(montant)),
            "currency": "XOF",
            "externalId": reference_interne,
            "payer": {
                "partyIdType": "MSISDN",
                "partyId": numero_normalize,
            },
            "payerMessage": description,
            "payeeNote": f"Ref: {reference_interne}",
        }

        try:
            response = requests.post(
                f"{self.base_url}/collection/v1_0/requesttopay",
                json=payload,
                headers={
                    "Authorization": f"Bearer {self._get_access_token()}",
                    "X-Reference-Id": reference_uuid,
                    "X-Target-Environment": "production",
                    "Ocp-Apim-Subscription-Key": self.subscription_key,
                    "Content-Type": "application/json",
                },
                timeout=15
            )

            if response.status_code == 202:
                return ResultatTransaction(
                    succes=True,
                    reference=reference_uuid,
                    message="Demande MTN MoMo acceptée – en attente confirmation",
                    donnees_brutes={"reference_id": reference_uuid},
                )

            return ResultatTransaction(
                succes=False,
                reference="",
                message=f"MTN MoMo erreur HTTP {response.status_code}",
                donnees_brutes={"body": response.text},
            )

        except requests.exceptions.Timeout:
            return ResultatTransaction(False, "", "Timeout MTN MoMo")
        except Exception as e:
            return ResultatTransaction(False, "", str(e))

    def _get_access_token(self) -> str:
        """Récupère le Bearer token MTN MoMo."""
        response = requests.post(
            f"{self.base_url}/collection/token/",
            auth=(
                current_app.config.get("MTN_API_USER", ""),
                current_app.config.get("MTN_API_KEY", "")
            ),
            headers={"Ocp-Apim-Subscription-Key": self.subscription_key},
            timeout=10
        )
        return response.json().get("access_token", "")


# ============================================================
# FACTORY – choisit le bon service selon l'opérateur
# ============================================================
def get_service_mobile_money(operateur: str):
    """
    Retourne le service Mobile Money adapté.
    operateur : 'wave' | 'orange' | 'mtn'
    """
    services = {
        "wave": WaveService,
        "orange": OrangeMoneyService,
        "mtn": MTNMoMoService,
    }
    service_class = services.get(operateur.lower())
    if not service_class:
        raise ValueError(f"Opérateur '{operateur}' non supporté. Choisir : wave, orange, mtn")
    return service_class()
