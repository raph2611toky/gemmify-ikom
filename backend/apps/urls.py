# apps/urls.py
from fastapi import APIRouter

from .views import chat_view, generate_tutorial_view

router = APIRouter()


# ── Chat MPANABE AI ───────────────────────────────────────────────────────────
router.post(
    "/api/gemmify-ikom/chat/",
    tags=["Gemmify IKOM"],
    summary="Chat avec MPANABE AI",
    responses={
        200: {
            "description": "Réponse de l'IA",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "response": "{\"reponse\": \"...\", \"action\": null, \"choix\": []}"
                    }
                }
            }
        },
        500: {"description": "Erreur serveur"}
    }
)(chat_view)


# ── Génération de tutoriel vidéo ──────────────────────────────────────────────
router.post(
    "/api/gemmify-ikom/generate-tutorial/",
    tags=["Gemmify IKOM"],
    summary="Générer un tutoriel vidéo pédagogique",
    responses={
        200: {
            "description": "Vidéo générée avec succès",
            "content": {
                "application/json": {
                    "example": {
                        "success":   True,
                        "video_url": "http://localhost:8000/media/tutorials/tutorial_abc123.mp4",
                        "script":    "Salama! Anio isika hiresaka momba ny ...",
                        "sujet":     "Les fractions",
                        "duree_max": 60,
                        "voix":      "MASCULIN"
                    }
                }
            }
        },
        400: {"description": "Paramètre invalide"},
        422: {"description": "Échec de génération"},
        500: {"description": "Erreur serveur"}
    }
)(generate_tutorial_view)