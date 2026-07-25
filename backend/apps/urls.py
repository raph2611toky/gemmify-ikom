from fastapi import APIRouter

from .views import chat_view

router = APIRouter()

router.post(
    "/api/gemmify-ikom/chat/",
    tags=["Gemmify IKOM"],
    summary="Chat avec MPANABE AI"
)(chat_view)