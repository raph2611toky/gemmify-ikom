# app.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pathlib import Path

from apps.urls import router

import os


BASE_DIR = Path(__file__).resolve().parent
MEDIA_DIR = os.path.join(BASE_DIR, "media")

os.makedirs(os.path.join(MEDIA_DIR, "tutorials"), exist_ok=True)
os.makedirs(os.path.join(MEDIA_DIR, "temp"), exist_ok=True)
os.makedirs(os.path.join(MEDIA_DIR, "videos", "audios"), exist_ok=True)


app = FastAPI(
    title="Gemmify IKOM API",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


app.mount(
    "/media",
    StaticFiles(directory=MEDIA_DIR),
    name="media"
)


app.include_router(router)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=8000,
        reload=True
    )