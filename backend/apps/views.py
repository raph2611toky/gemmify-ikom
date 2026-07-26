# apps/views.py
from typing import List, Annotated

from fastapi import UploadFile, File, Form, Request
from fastapi.responses import JSONResponse

from helpers.ai.gemma import simple_chat_gemma
from helpers.videos.create_tutorial import create_dynamic_tutorial

from pathlib import Path
import os
import traceback


# ── Chat MPANABE AI ───────────────────────────────────────────────────────────

async def chat_view(
    texte: Annotated[str, Form(description="Message à envoyer à MPANABE AI")],
    fichiers: Annotated[
        List[UploadFile],
        File(description="Fichiers joints (images, PDF, texte, etc.) — optionnel")
    ] = None
):
    try:
        if fichiers is None:
            fichiers = []
        fichiers_valides = [
            f for f in fichiers
            if f and f.filename and f.filename.strip()
        ]

        response = await simple_chat_gemma(
            message=texte,
            files=fichiers_valides
        )

        return JSONResponse(
            status_code=200,
            content={
                "success": True,
                "response": response
            }
        )

    except Exception as e:
        print(traceback.format_exc())
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "message": str(e)
            }
        )


# ── Génération de tutoriel vidéo ──────────────────────────────────────────────

async def generate_tutorial_view(
    request: Request,
    sujet: Annotated[
        str,
        Form(description="Le sujet du tutoriel (leçon, devoir, quiz, activité...)")
    ],
    contexte: Annotated[
        str,
        Form(description="Contexte de l'élève : parcours, niveau, matière, etc.")
    ] = "",
    sexe: Annotated[
        str,
        Form(description="Voix : MASCULIN ou FEMININ")
    ] = "MASCULIN",
    max_duration: Annotated[
        int,
        Form(
            description="Durée maximale de la vidéo en secondes (15 à 120)",
            ge=15,
            le=120
        )
    ] = 60
):
    try:
        sexe = sexe.upper().strip()
        if sexe not in ("MASCULIN", "FEMININ"):
            return JSONResponse(
                status_code=400,
                content={
                    "success": False,
                    "message": "Le champ 'sexe' doit être 'MASCULIN' ou 'FEMININ'."
                }
            )
        sujet_complet = sujet.strip()
        if contexte.strip():
            sujet_complet = (
                f"{sujet.strip()}\n\n"
                f"Contexte de l'élève : {contexte.strip()}"
            )

        print(f"[VIEW] Génération tutoriel : '{sujet_complet[:80]}'")
        result = create_dynamic_tutorial(
            sujet=sujet_complet,
            sexe=sexe,
            max_duration=max_duration
        )

        if isinstance(result, dict):
            return JSONResponse(
                status_code=422,
                content={
                    "success": False,
                    "message": result.get("error", "Erreur inconnue lors de la génération.")
                }
            )
        
        video_path, script = result

        if not video_path or not os.path.exists(video_path):
            return JSONResponse(
                status_code=500,
                content={
                    "success": False,
                    "message": "La vidéo a été générée mais le fichier est introuvable."
                }
            )

        base_dir      = Path(__file__).resolve().parent.parent
        media_dir     = os.path.join(base_dir, "media")
        relative_path = os.path.relpath(video_path, media_dir)

        relative_path = relative_path.replace(os.sep, "/")

        base_url  = str(request.base_url).rstrip("/")
        video_url = f"{base_url}/media/{relative_path}"

        print(f"[VIEW] Vidéo disponible : {video_url}")

        return JSONResponse(
            status_code=200,
            content={
                "success":   True,
                "video_url": video_url,
                "script":    script,
                "sujet":     sujet.strip(),
                "duree_max": max_duration,
                "voix":      sexe
            }
        )

    except Exception as e:
        print(traceback.format_exc())
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "message": f"Erreur serveur : {str(e)}"
            }
        )