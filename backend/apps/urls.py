# apps/urls.py
from fastapi import APIRouter

from .views import chat_view, generate_tutorial_view

router = APIRouter()


router.post(
    "/api/gemmify-ikom/chat/",
    tags=["Gemmify IKOM"],
    summary="Chat avec MPANABE AI"
)(chat_view)


router.post(
    "/api/gemmify-ikom/generate-tutorial/",
    tags=["Gemmify IKOM"],
    summary="Générer un tutoriel vidéo pédagogique"
)(generate_tutorial_view)