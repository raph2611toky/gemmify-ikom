# apps/views.py
from typing import List, Annotated

from fastapi import UploadFile, File, Form, Request
from fastapi.responses import JSONResponse

from helpers.ai.gemma import simple_chat_gemma
from helpers.videos.create_tutorial import create_dynamic_tutorial, decide_video_reuse
from helpers.db.tutorials_repository import (
    insert_tutorial,
    get_tutorials_by_contexte,
    get_tutorial_by_id,
)
from pathlib import Path
import os
import traceback


BASE_DIR  = Path(__file__).resolve().parent.parent
MEDIA_DIR = os.path.join(BASE_DIR, "media")
RAKIBOLANA_PATH = os.path.join(MEDIA_DIR, "rakibolana-dikan-teny-vf-vm.pdf")


def _get_rakibolana_upload_file() -> UploadFile:
    f = open(RAKIBOLANA_PATH, "rb")
    return UploadFile(
        file=f,
        filename="rakibolana-dikan-teny-vf-vm.pdf",
    )


# ── Chat MPANABE AI ───────────────────────────────────────────────────────────

async def chat_view(
    texte: Annotated[str, Form(description="Message à envoyer à MPANABE AI")],
    with_rag: Annotated[
        bool,
        Form(description="Si True, attache automatiquement le rakibolana (dictionnaire malagasy) comme source RAG")
    ] = False,
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

        if with_rag:
            if not os.path.exists(RAKIBOLANA_PATH):
                return JSONResponse(
                    status_code=500,
                    content={
                        "success": False,
                        "message": "Fichier RAG (rakibolana) introuvable sur le serveur."
                    }
                )
            fichiers_valides.append(_get_rakibolana_upload_file())

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

# async def generate_tutorial_view(
#     request: Request,
#     sujet: Annotated[
#         str,
#         Form(description="Le sujet du tutoriel (leçon, devoir, quiz, activité...)")
#     ],
#     contexte: Annotated[
#         str,
#         Form(description="Contexte de l'élève : parcours, niveau, matière, etc.")
#     ] = "",
#     sexe: Annotated[
#         str,
#         Form(description="Voix : MASCULIN ou FEMININ")
#     ] = "MASCULIN",
#     max_duration: Annotated[
#         int,
#         Form(
#             description="Durée maximale de la vidéo en secondes (15 à 120)",
#             ge=15,
#             le=120
#         )
#     ] = 60
# ):
#     try:
#         sexe = sexe.upper().strip()
#         if sexe not in ("MASCULIN", "FEMININ"):
#             return JSONResponse(
#                 status_code=400,
#                 content={
#                     "success": False,
#                     "message": "Le champ 'sexe' doit être 'MASCULIN' ou 'FEMININ'."
#                 }
#             )
#         sujet_complet = sujet.strip()
#         if contexte.strip():
#             sujet_complet = (
#                 f"{sujet.strip()}\n\n"
#                 f"Contexte de l'élève : {contexte.strip()}"
#             )

#         print(f"[VIEW] Génération tutoriel : '{sujet_complet[:80]}'")
#         result = create_dynamic_tutorial(
#             sujet=sujet_complet,
#             sexe=sexe,
#             max_duration=max_duration
#         )

#         if isinstance(result, dict):
#             return JSONResponse(
#                 status_code=422,
#                 content={
#                     "success": False,
#                     "message": result.get("error", "Erreur inconnue lors de la génération.")
#                 }
#             )
        
#         video_path, script = result

#         if not video_path or not os.path.exists(video_path):
#             return JSONResponse(
#                 status_code=500,
#                 content={
#                     "success": False,
#                     "message": "La vidéo a été générée mais le fichier est introuvable."
#                 }
#             )

#         base_dir      = Path(__file__).resolve().parent.parent
#         media_dir     = os.path.join(base_dir, "media")
#         relative_path = os.path.relpath(video_path, media_dir)

#         relative_path = relative_path.replace(os.sep, "/")

#         base_url  = str(request.base_url).rstrip("/")
#         video_url = f"{base_url}/media/{relative_path}"

#         print(f"[VIEW] Vidéo disponible : {video_url}")

#         return JSONResponse(
#             status_code=200,
#             content={
#                 "success":   True,
#                 "video_url": video_url,
#                 "script":    script,
#                 "sujet":     sujet.strip(),
#                 "duree_max": max_duration,
#                 "voix":      sexe
#             }
#         )

#     except Exception as e:
#         print(traceback.format_exc())
#         return JSONResponse(
#             status_code=500,
#             content={
#                 "success": False,
#                 "message": f"Erreur serveur : {str(e)}"
#             }
#         )

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
    ] = 60,
    email: Annotated[
        str | None,
        Form(description="Email de la personne qui crée le tutoriel (optionnel)")
    ] = None
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

        email_normalise = email.strip() if email and email.strip() else None

        sujet_complet = sujet.strip()
        if contexte.strip():
            sujet_complet = (
                f"{sujet.strip()}\n\n"
                f"Contexte de l'élève : {contexte.strip()}"
            )

        base_dir  = Path(__file__).resolve().parent.parent
        media_dir = os.path.join(base_dir, "media")
        base_url  = str(request.base_url).rstrip("/")

        # ── 1. Vérifier les vidéos déjà existantes pour ce contexte ──────────
        existing_videos = get_tutorials_by_contexte(contexte)
        decision = decide_video_reuse(sujet.strip(), contexte.strip(), existing_videos)

        if decision.get("action") == "reutiliser_video" and decision.get("video_id"):
            existing = get_tutorial_by_id(decision["video_id"])

            if existing and os.path.exists(existing["video_path"]):
                relative_path = os.path.relpath(existing["video_path"], media_dir)
                relative_path = relative_path.replace(os.sep, "/")
                video_url = f"{base_url}/media/{relative_path}"

                print(f"[VIEW] Réutilisation vidéo existante (id={existing['id']}) : {video_url}")

                return JSONResponse(
                    status_code=200,
                    content={
                        "success":   True,
                        "action":    "video_existante",
                        "video_url": video_url,
                        "script":    existing["script"],
                        "sujet":     existing["sujet"],
                        "duree_max": existing["duree_max"],
                        "voix":      existing["sexe"],
                        "raison":    decision.get("raison", "")
                    }
                )

            print(
                f"[WARN] Vidéo existante id={decision.get('video_id')} "
                f"introuvable sur disque, création d'une nouvelle vidéo."
            )

        # ── 2. Sinon, créer une nouvelle vidéo (processus déjà fonctionnel) ──
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

        # ── 3. Sauvegarder en base ────────────────────────────────────────
        try:
            insert_tutorial(
                sujet=sujet.strip(),
                contexte=contexte.strip(),
                duree_max=max_duration,
                video_path=video_path,
                script=script,
                sexe=sexe,
                email=email_normalise,
            )
        except Exception:
            # On ne bloque pas la réponse si la sauvegarde échoue
            print(traceback.format_exc())

        relative_path = os.path.relpath(video_path, media_dir)
        relative_path = relative_path.replace(os.sep, "/")
        video_url = f"{base_url}/media/{relative_path}"

        print(f"[VIEW] Vidéo disponible : {video_url}")

        return JSONResponse(
            status_code=200,
            content={
                "success":   True,
                "action":    "video_creee",
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
