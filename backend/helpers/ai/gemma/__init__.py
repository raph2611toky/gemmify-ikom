# helpers/ai/gemma/__init__.py
from typing import List

import os
import json
import base64
import asyncio
import traceback

from dotenv import load_dotenv
from fastapi import UploadFile

from .constante import GEMMA_MPANABE_SYSTEM_PROMPT


load_dotenv()


# ══════════════════════════════════════════════════════════════════════════
# ── ANCIENNE VERSION : modèle hébergé via l'API Gemini (OpenAI-compatible) ──
# ══════════════════════════════════════════════════════════════════════════
#
# from openai import OpenAI
#
# GOOGLE_API_KEY_AI = os.getenv("GOOGLE_API_KEY_AI")
#
# client = OpenAI(
#     api_key=GOOGLE_API_KEY_AI,
#     base_url="https://generativelanguage.googleapis.com/v1beta/openai/"
# )
#
#
# async def simple_chat_gemma(
#     message: str,
#     files: List[UploadFile] | None = None
# ) -> str:
#
#     if not message:
#         return {
#             "reponse": "Message requis.",
#             "action": None,
#             "choix": []
#         }
#
#     if files is None:
#         files = []
#
#     try:
#
#         user_content = [
#             {
#                 "type": "text",
#                 "text": message
#             }
#         ]
#
#         for file in files:
#             if not file or not file.filename:
#                 continue
#
#             bloc = await _process_file(file)
#
#             if bloc is not None:
#                 user_content.append(bloc)
#
#         response = client.chat.completions.create(
#             model="gemma-4-31b-it",
#             messages=[
#                 {
#                     "role": "system",
#                     "content": GEMMA_MPANABE_SYSTEM_PROMPT
#                 },
#                 {
#                     "role": "user",
#                     "content": user_content
#                 }
#             ]
#         )
#
#         return response.choices[0].message.content
#
#     except Exception:
#
#         print(traceback.format_exc())
#
#         return {
#             "reponse": "Nisy olana tamin'ny fifandraisana tamin'ny IA.",
#             "action": None,
#             "choix": []
#         }


# ══════════════════════════════════════════════════════════════════════════
# ── NOUVELLE VERSION : modèle fine-tuné chargé localement (Unsloth / LoRA) ──
# ══════════════════════════════════════════════════════════════════════════

from unsloth import FastModel

HF_REPO = "Nandrasana2611/mpanabe-gemma2b-lora"
MAX_SEQ_LENGTH = 2048
MAX_NEW_TOKENS = 400

# Chargé une seule fois en mémoire (singleton), idéalement au démarrage
# du serveur via preload_model() plutôt qu'au premier appel de chat.
_model = None
_tokenizer = None


def _get_model():
    global _model, _tokenizer

    if _model is None:
        print(f"[INFO] Chargement du modèle fine-tuné depuis {HF_REPO}...")

        _model, _tokenizer = FastModel.from_pretrained(
            model_name=HF_REPO,
            max_seq_length=MAX_SEQ_LENGTH,
            load_in_4bit=True,
        )
        FastModel.for_inference(_model)

        print("[INFO] Modèle fine-tuné chargé avec succès.")

    return _model, _tokenizer


def preload_model() -> None:
    """
    Force le chargement du modèle dès maintenant, plutôt que d'attendre
    la première requête de chat. À appeler depuis app.py au démarrage
    du serveur (évènement 'startup'), pour que la première requête d'un
    utilisateur ne subisse pas le temps de chargement du modèle.
    """
    _get_model()


IMAGE_MIME_TYPES = {
    "image/jpeg",
    "image/jpg",
    "image/png",
    "image/gif",
    "image/webp",
    "image/heic",
    "image/heif",
}

TEXT_MIME_TYPES = {
    "text/plain",
    "text/markdown",
    "text/csv",
    "text/html",
    "text/xml",
    "application/json",
    "application/xml",
}

PDF_MIME_TYPES = {
    "application/pdf",
}


async def _process_file(file: UploadFile) -> str | None:
    """
    NOTE : le modèle fine-tuné local est un modèle texte (conversations
    Malagasy). Contrairement à l'ancienne version basée sur l'API Gemini,
    les images et PDF ne peuvent pas être "vus" par ce modèle : seul le
    texte peut être injecté dans le contexte. Les images sont donc
    ignorées ici (on ne fait qu'informer le modèle qu'un fichier a été
    joint), pour éviter de lui envoyer du base64 qu'il ne sait pas
    interpréter.
    """
    try:
        content = await file.read()

        if not content:
            return None

        mime_type = file.content_type or "application/octet-stream"

        if mime_type in TEXT_MIME_TYPES:
            try:
                text_content = content.decode("utf-8")
            except UnicodeDecodeError:
                text_content = content.decode("latin-1", errors="replace")

            return f"[Fichier : {file.filename}]\n{text_content}"

        if mime_type in IMAGE_MIME_TYPES or mime_type in PDF_MIME_TYPES:
            print(
                f"[WARN] Fichier '{file.filename}' ({mime_type}) ignoré : "
                f"le modèle local ne traite que du texte."
            )
            return (
                f"[Fichier joint ignoré : {file.filename} — "
                f"type '{mime_type}' non pris en charge par le modèle local]"
            )

        return (
            f"[Fichier joint : {file.filename} | type : {mime_type} — "
            f"contenu non lisible par le modèle local]"
        )

    except Exception:
        print(f"[ERREUR] Impossible de lire le fichier {file.filename}")
        print(traceback.format_exc())
        return None


def _clean_json_response(raw: str) -> str:
    raw = raw.strip()
    raw = raw.removeprefix("```json").removeprefix("```")
    raw = raw.removesuffix("```")
    raw = raw.strip()
    start = raw.find("{")
    end = raw.rfind("}")
    if start != -1 and end != -1 and end > start:
        raw = raw[start:end + 1]
    return raw.strip()


def _generate_sync(full_message: str) -> str:
    """
    Génération bloquante (CPU/GPU-bound), à lancer dans un thread séparé
    via asyncio.to_thread pour ne pas geler l'event loop de FastAPI.
    """
    model, tokenizer = _get_model()

    messages = [
        {"role": "system", "content": GEMMA_MPANABE_SYSTEM_PROMPT},
        {"role": "user", "content": full_message},
    ]

    inputs = tokenizer.apply_chat_template(
        messages,
        tokenize=True,
        add_generation_prompt=True,
        return_tensors="pt",
    ).to(model.device)

    outputs = model.generate(
        input_ids=inputs,
        max_new_tokens=MAX_NEW_TOKENS,
        temperature=0.7,
        top_p=0.9,
        do_sample=True,
        pad_token_id=tokenizer.eos_token_id,
    )

    return tokenizer.decode(
        outputs[0][inputs.shape[-1]:],
        skip_special_tokens=True,
    )


async def simple_chat_gemma(
    message: str,
    files: List[UploadFile] | None = None
) -> str:

    if not message:
        return {
            "reponse": "Message requis.",
            "action": None,
            "choix": []
        }

    if files is None:
        files = []

    try:
        full_message = message

        for file in files:
            if not file or not file.filename:
                continue

            bloc = await _process_file(file)

            if bloc is not None:
                full_message = f"{full_message}\n\n{bloc}"

        # generate() est bloquant : on le sort de l'event loop asyncio
        raw = await asyncio.to_thread(_generate_sync, full_message)

        cleaned = _clean_json_response(raw)

        try:
            return json.loads(cleaned)
        except json.JSONDecodeError:
            # Si le modèle ne retourne pas un JSON strict, on renvoie
            # quand même le texte brut plutôt que d'échouer.
            print(f"[WARN] Réponse non-JSON du modèle local : {raw[:200]}")
            return {
                "reponse": raw.strip(),
                "action": None,
                "choix": []
            }

    except Exception:

        print(traceback.format_exc())

        return {
            "reponse": "Nisy olana tamin'ny fifandraisana tamin'ny IA.",
            "action": None,
            "choix": []
        }