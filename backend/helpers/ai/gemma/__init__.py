# helpers/ai/gemma/__init__.py
from typing import List

import os
import base64
import traceback

from dotenv import load_dotenv
from fastapi import UploadFile
from openai import OpenAI

from .constante import GEMMA_MPANABE_SYSTEM_PROMPT


load_dotenv()

GOOGLE_API_KEY_AI = os.getenv("GOOGLE_API_KEY_AI")


client = OpenAI(
    api_key=GOOGLE_API_KEY_AI,
    base_url="https://generativelanguage.googleapis.com/v1beta/openai/"
)


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


async def _process_file(file: UploadFile) -> dict | None:
    try:
        content = await file.read()

        if not content:
            return None

        mime_type = file.content_type or "application/octet-stream"

        if mime_type in IMAGE_MIME_TYPES:
            b64 = base64.b64encode(content).decode("utf-8")
            return {
                "type": "image_url",
                "image_url": {
                    "url": f"data:{mime_type};base64,{b64}"
                }
            }

        if mime_type in TEXT_MIME_TYPES:
            try:
                text_content = content.decode("utf-8")
            except UnicodeDecodeError:
                text_content = content.decode("latin-1", errors="replace")

            return {
                "type": "text",
                "text": (
                    f"[Fichier : {file.filename}]\n"
                    f"{text_content}"
                )
            }

        if mime_type in PDF_MIME_TYPES:
            b64 = base64.b64encode(content).decode("utf-8")
            return {
                "type": "text",
                "text": (
                    f"[Fichier PDF joint : {file.filename}]\n"
                    f"data:{mime_type};base64,{b64}"
                )
            }

        b64 = base64.b64encode(content).decode("utf-8")
        return {
            "type": "text",
            "text": (
                f"[Fichier joint : {file.filename} | type : {mime_type}]\n"
                f"data:{mime_type};base64,{b64}"
            )
        }

    except Exception:
        print(f"[ERREUR] Impossible de lire le fichier {file.filename}")
        print(traceback.format_exc())
        return None


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

        user_content = [
            {
                "type": "text",
                "text": message
            }
        ]

        for file in files:
            if not file or not file.filename:
                continue

            bloc = await _process_file(file)

            if bloc is not None:
                user_content.append(bloc)

        response = client.chat.completions.create(
            model="gemma-4-31b-it",
            messages=[
                {
                    "role": "system",
                    "content": GEMMA_MPANABE_SYSTEM_PROMPT
                },
                {
                    "role": "user",
                    "content": user_content
                }
            ]
        )

        return response.choices[0].message.content

    except Exception:

        print(traceback.format_exc())

        return {
            "reponse": "Nisy olana tamin'ny fifandraisana tamin'ny IA.",
            "action": None,
            "choix": []
        }