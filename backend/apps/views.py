from typing import List

from fastapi import UploadFile
from fastapi import File
from fastapi import Form
from fastapi.responses import JSONResponse

from helpers.ai.gemma import simple_chat_gemma


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