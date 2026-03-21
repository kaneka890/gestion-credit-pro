"""
Service de Notifications – WhatsApp Business API (Meta)
Plus fiable que les SMS en zone dense (Treichville, Adjamé, Yopougon).
"""
import requests
from flask import current_app


class WhatsAppService:
    """Envoi de messages WhatsApp via Meta Cloud API."""

    def _headers(self):
        token = current_app.config["WHATSAPP_TOKEN"]
        return {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }

    def _url(self):
        phone_id = current_app.config["WHATSAPP_PHONE_ID"]
        return f"https://graph.facebook.com/v19.0/{phone_id}/messages"

    def envoyer_contrat_cree(self, telephone: str, nom_client: str, montant: float, date_echeance: str) -> bool:
        """Notification de création de contrat."""
        message = (
            f"✅ *Crédit accordé !*\n\n"
            f"Bonjour {nom_client},\n"
            f"Votre crédit de *{montant:,.0f} FCFA* a été enregistré.\n"
            f"Date limite de remboursement : *{date_echeance}*\n\n"
            f"_Gestion Crédit Pro – Votre confiance, notre mission._"
        )
        return self._envoyer_texte(telephone, message)

    def envoyer_rappel_paiement(self, telephone: str, nom_client: str, montant_du: float, date_limite: str) -> bool:
        """Rappel de paiement (J-1 avant échéance)."""
        message = (
            f"⏰ *Rappel de paiement*\n\n"
            f"Bonjour {nom_client},\n"
            f"Votre paiement de *{montant_du:,.0f} FCFA* est dû le *{date_limite}*.\n"
            f"Pensez à alimenter votre compte Mobile Money !\n\n"
            f"_Merci pour votre confiance._"
        )
        return self._envoyer_texte(telephone, message)

    def envoyer_confirmation_paiement(
        self, telephone: str, nom_client: str, montant: float, solde_restant: float, reference: str
    ) -> bool:
        """Reçu de paiement après confirmation Mobile Money."""
        message = (
            f"💚 *Paiement reçu !*\n\n"
            f"Bonjour {nom_client},\n"
            f"Paiement de *{montant:,.0f} FCFA* confirmé.\n"
            f"Référence : `{reference}`\n"
            f"Solde restant : *{solde_restant:,.0f} FCFA*\n\n"
        )
        if solde_restant <= 0:
            message += "🎉 *Votre crédit est soldé ! Merci !*\n"
        message += "_Gestion Crédit Pro_"
        return self._envoyer_texte(telephone, message)

    def envoyer_alerte_retard(self, telephone: str, nom_client: str, montant_du: float) -> bool:
        """Alerte retard de paiement."""
        message = (
            f"🔴 *Retard de paiement*\n\n"
            f"Bonjour {nom_client},\n"
            f"Votre paiement de *{montant_du:,.0f} FCFA* est en retard.\n"
            f"Veuillez contacter votre commerçant dès que possible.\n\n"
            f"_Régularisez rapidement pour maintenir votre score de confiance._"
        )
        return self._envoyer_texte(telephone, message)

    def _envoyer_texte(self, telephone: str, message: str) -> bool:
        """Envoi d'un message texte WhatsApp."""
        numero = telephone if telephone.startswith("+") else f"+{telephone}"

        payload = {
            "messaging_product": "whatsapp",
            "to": numero,
            "type": "text",
            "text": {"body": message, "preview_url": False},
        }

        try:
            response = requests.post(
                self._url(),
                json=payload,
                headers=self._headers(),
                timeout=10
            )
            return response.status_code == 200
        except Exception:
            # Ne pas faire planter l'application si WhatsApp est indisponible
            current_app.logger.warning(f"WhatsApp indisponible pour {telephone}")
            return False
