# apps/views.py
from typing import List

from fastapi import UploadFile, File, Form, Request
from fastapi.responses import JSONResponse

from helpers.ai.gemma import simple_chat_gemma
from helpers.videos.create_tutorial import create_dynamic_tutorial

import os
import traceback


# ── Chat MPANABE AI ──────────────────────────────────────────────────────────

async def chat_view(
    texte: str = Form(...),
    fichiers: List[UploadFile] = File(default=[])
):
    try:

        response = await simple_chat_gemma(
            message=texte,
            files=fichiers
        )

        return JSONResponse(
            status_code=200,
            content={
                "success": True,
                "response": response
            }
        )

    except Exception as e:

        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "message": str(e)
            }
        )


# ── Génération de tutoriel vidéo ─────────────────────────────────────────────

async def generate_tutorial_view(
    request: Request,
    sujet: str = Form(..., description="Le sujet du tutoriel (leçon, devoir, quiz, activité...)"),
    contexte: str = Form(
        default="",
        description="Contexte additionnel : parcours de l'élève, niveau, matière, etc."
    ),
    sexe: str = Form(
        default="MASCULIN",
        description="Voix : MASCULIN ou FEMININ"
    ),
    max_duration: int = Form(
        default=60,
        description="Durée maximale de la vidéo en secondes",
        ge=15,
        le=120
    )
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

        from pathlib import Path
        base_dir = Path(__file__).resolve().parent.parent
        media_dir = os.path.join(base_dir, "media")
        relative_path = os.path.relpath(video_path, media_dir)

        base_url = str(request.base_url).rstrip("/")
        video_url = f"{base_url}/media/{relative_path}"

        return JSONResponse(
            status_code=200,
            content={
                "success": True,
                "video_url": video_url,
                "script": script,
                "sujet": sujet.strip(),
                "duree_max": max_duration,
                "voix": sexe
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
