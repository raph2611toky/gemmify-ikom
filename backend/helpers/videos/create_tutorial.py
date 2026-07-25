# helpers/videos/create_tutorial.py

from helpers.videos import add_subtitles_to_video, get_random_name, voice_to_text_with_timestamps
from helpers.evenlabs import text_to_speech, voices, text_to_speech_with_timestamps
from helpers.ai.gemma.constante import GEMMA_TUTORIAL_SYSTEM_PROMPT
from pydub import AudioSegment
from moviepy.editor import VideoFileClip, AudioFileClip, ImageClip, concatenate_videoclips
from pathlib import Path
from openai import OpenAI
from dotenv import load_dotenv
import numpy as np
import traceback
import random
import json
import cv2
import os
import re

load_dotenv()

# ── Chemins ──────────────────────────────────────────────────────────────────

BASE_DIR       = Path(__file__).resolve().parent.parent.parent
MEDIA_ROOT     = os.path.join(BASE_DIR, 'media', 'tutorials')
TEMP_ROOT      = os.path.join(BASE_DIR, 'media', 'temp')
DATASETS_ROOT  = os.path.join(BASE_DIR, 'helpers', 'videos', 'datasets', 'images')

# ── Client Gemma ─────────────────────────────────────────────────────────────

client = OpenAI(
    api_key=os.getenv("GOOGLE_API_KEY_AI_VIDEO_GENERATOR"),
    base_url="https://generativelanguage.googleapis.com/v1beta/openai/"
)

# ── Constantes vidéo ─────────────────────────────────────────────────────────

FRAME_WIDTH  = 1280
FRAME_HEIGHT = 720
FPS          = 30


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _get_available_folders() -> list[str]:
    """
    Scanne récursivement le dossier datasets/images
    et retourne tous les dossiers contenant au moins une image PNG.
    """
    folders = []
    for root, dirs, files in os.walk(DATASETS_ROOT):
        if any(f.endswith('.png') for f in files):
            # Chemin relatif depuis DATASETS_ROOT
            rel = os.path.relpath(root, DATASETS_ROOT)
            folders.append(rel)
    return sorted(folders)


def _get_images_in_folder(folder_rel: str) -> list[str]:
    """
    Retourne tous les chemins d'images PNG dans un dossier relatif.
    """
    folder_abs = os.path.join(DATASETS_ROOT, folder_rel)
    if not os.path.exists(folder_abs):
        return []
    return [
        os.path.join(folder_abs, f)
        for f in os.listdir(folder_abs)
        if f.endswith('.png')
    ]


def _clean_json_response(raw: str) -> str:
    """
    Nettoie la réponse de Gemma : supprime les blocs markdown si présents.
    """
    raw = raw.strip()
    # Supprime ```json ... ``` ou ``` ... ```
    raw = re.sub(r'^```(?:json)?\s*', '', raw)
    raw = re.sub(r'\s*```$', '', raw)
    return raw.strip()


def _ask_gemma_for_tutorial_plan(sujet: str, folders: list[str]) -> dict | None:
    folders_str = "\n".join(f"- {f}" for f in folders)
    system_prompt = GEMMA_TUTORIAL_SYSTEM_PROMPT.replace(
        "{folders_disponibles}", folders_str
    )

    try:
        response = client.chat.completions.create(
            model="gemma-4-31b-it",
            messages=[
                {
                    "role": "system",
                    "content": system_prompt
                },
                {
                    "role": "user",
                    "content": (
                        f"Crée un tutoriel pédagogique pour enfants sur le sujet suivant : "
                        f"'{sujet}'. Réponds uniquement en JSON valide."
                    )
                }
            ]
        )

        raw = response.choices[0].message.content
        cleaned = _clean_json_response(raw)
        return json.loads(cleaned)

    except json.JSONDecodeError as e:
        print(f"[ERREUR JSON] Réponse Gemma invalide : {e}")
        print(f"Réponse brute : {raw}")
        return None
    except Exception:
        print(traceback.format_exc())
        return None


def _build_slide_frame(image_paths: list[str]) -> np.ndarray:
    """
    Construit un frame numpy (H x W x 3) à partir d'une liste d'images.
    Gère la transparence PNG et la mise en page en grille.
    """
    composite = np.ones((FRAME_HEIGHT, FRAME_WIDTH, 3), dtype=np.uint8) * 255

    if not image_paths:
        return composite

    num_images = len(image_paths)
    grid_cols  = min(num_images, 2)
    grid_rows  = (num_images + grid_cols - 1) // grid_cols
    img_w      = FRAME_WIDTH  // grid_cols
    img_h      = FRAME_HEIGHT // grid_rows

    for i, img_path in enumerate(image_paths):
        img = cv2.imread(img_path, cv2.IMREAD_UNCHANGED)
        if img is None:
            continue

        # Gestion transparence
        if img.ndim == 3 and img.shape[2] == 4:
            alpha    = img[:, :, 3] / 255.0
            img_rgb  = img[:, :, :3]
        else:
            alpha    = np.ones(img.shape[:2], dtype=np.float32)
            img_rgb  = img if img.ndim == 3 else cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)

        # Redimensionnement avec ratio conservé
        src_h, src_w = img_rgb.shape[:2]
        target_w = img_w - 20
        target_h = img_h - 20
        ratio    = min(target_w / src_w, target_h / src_h)
        new_w    = int(src_w * ratio)
        new_h    = int(src_h * ratio)

        img_resized   = cv2.resize(img_rgb,  (new_w, new_h), interpolation=cv2.INTER_AREA)
        alpha_resized = cv2.resize(alpha,    (new_w, new_h), interpolation=cv2.INTER_AREA)

        # Position dans la grille
        row = i // grid_cols
        col = i % grid_cols
        x   = col * img_w + (img_w - new_w) // 2
        y   = row * img_h + (img_h - new_h) // 2

        # Vérification des bornes
        x_end = min(x + new_w, FRAME_WIDTH)
        y_end = min(y + new_h, FRAME_HEIGHT)
        new_w = x_end - x
        new_h = y_end - y

        if new_w <= 0 or new_h <= 0:
            continue

        img_resized   = img_resized[:new_h, :new_w]
        alpha_resized = alpha_resized[:new_h, :new_w]

        for c in range(3):
            composite[y:y_end, x:x_end, c] = (
                composite[y:y_end, x:x_end, c] * (1 - alpha_resized)
                + img_resized[:, :, c] * alpha_resized
            ).astype(np.uint8)

    return cv2.cvtColor(composite, cv2.COLOR_BGR2RGB)


def _build_timestamps_from_audio(audio_path: str, voice_id: str, text: str) -> list[dict]:
    """
    Génère les segments de sous-titres depuis ElevenLabs ou Whisper en fallback.
    """
    timestamp_data = text_to_speech_with_timestamps(voice_id, text)

    if timestamp_data:
        alignment  = timestamp_data.get("alignment", {})
        chars      = alignment.get("chars", [])
        start_times = alignment.get("charStartTimesMs", [])
        durations  = alignment.get("charDurationsMs", [])

        if chars and start_times and durations and len(chars) == len(start_times) == len(durations):
            segments     = []
            current_text = ""
            current_start = None

            for i, (char, start_ms, dur_ms) in enumerate(zip(chars, start_times, durations)):
                if current_start is None:
                    current_start = start_ms / 1000.0
                current_text += char
                if char == " " or len(current_text) > 20 or i == len(chars) - 1:
                    segments.append({
                        "start": current_start,
                        "end":   (start_ms + dur_ms) / 1000.0,
                        "text":  current_text.strip()
                    })
                    current_text  = ""
                    current_start = None

            return segments

    # Fallback Whisper
    print("[INFO] Fallback vers Whisper pour les timestamps.")
    return voice_to_text_with_timestamps(audio_path) or []


# ─────────────────────────────────────────────────────────────────────────────
# Fonction principale
# ─────────────────────────────────────────────────────────────────────────────

def create_dynamic_tutorial(
    sujet: str,
    sexe: str = 'MASCULIN',
    max_duration: int = 60,
    output_filename: str | None = None
) -> tuple[str, str] | dict:
    """
    Génère une vidéo tutoriel pédagogique dynamique sur n'importe quel sujet.

    Args:
        sujet          : Le sujet libre du tutoriel (ex: "Les volcans", "La photosynthèse")
        sexe           : 'MASCULIN' ou 'FEMININ' pour la voix
        max_duration   : Durée maximale en secondes
        output_filename: Nom du fichier de sortie (optionnel)

    Returns:
        (chemin_video, texte_script) ou {"video_path": None, "error": "..."}
    """

    audio_path          = None
    temp_video_path     = None
    subtitled_video_path = None

    try:
        os.makedirs(MEDIA_ROOT, exist_ok=True)
        os.makedirs(TEMP_ROOT,  exist_ok=True)

        # ── 1. Scan des dossiers disponibles ─────────────────────────────────
        available_folders = _get_available_folders()
        if not available_folders:
            return {"video_path": None, "error": "Aucun dossier d'images trouvé dans datasets/"}

        print(f"[INFO] {len(available_folders)} dossiers d'images disponibles.")

        # ── 2. Gemma génère le plan pédagogique ──────────────────────────────
        print(f"[INFO] Génération du plan pédagogique pour : '{sujet}'")
        plan = _ask_gemma_for_tutorial_plan(sujet, available_folders)

        if not plan:
            return {"video_path": None, "error": "Échec de la génération du plan par Gemma"}

        script = plan.get("script", "").strip()
        slides = plan.get("slides", [])

        if not script:
            return {"video_path": None, "error": "Script vide généré par Gemma"}

        if not slides:
            return {"video_path": None, "error": "Aucune slide générée par Gemma"}

        print(f"[INFO] Script généré ({len(script.split())} mots), {len(slides)} slides.")
        print(f"[INFO] Script : {script[:100]}...")

        # ── 3. Génération audio via ElevenLabs ───────────────────────────────
        audio_filename = f"audio_{get_random_name()}.mp3"
        audio_path, voice_id = text_to_speech(
            text=script,
            sexe=sexe,
            output_filename=audio_filename
        )

        if not audio_path:
            return {"video_path": None, "error": "Échec de la génération audio"}

        audio_duration = AudioSegment.from_file(audio_path).duration_seconds
        total_duration = min(max_duration, audio_duration)
        print(f"[INFO] Durée audio : {audio_duration:.1f}s → durée vidéo : {total_duration:.1f}s")

        # ── 4. Timestamps pour sous-titres ───────────────────────────────────
        segments = _build_timestamps_from_audio(audio_path, voice_id, script)
        if not segments:
            print("[WARN] Aucun segment de sous-titres généré. Continuation sans sous-titres.")

        # ── 5. Construction des slides vidéo ─────────────────────────────────
        # Répartition proportionnelle des durées
        total_slides_duration = sum(s.get("duree_secondes", 10) for s in slides)
        video_clips = []

        for slide in slides:
            slide_folders  = slide.get("dossiers_images", [])
            slide_duration_raw = slide.get("duree_secondes", 10)

            # Proportionnel à la durée audio réelle
            slide_duration = (slide_duration_raw / total_slides_duration) * total_duration

            # Collecte des images depuis les dossiers choisis par Gemma
            slide_images = []
            for folder in slide_folders:
                # Validation : dossier autorisé ?
                if folder not in available_folders:
                    print(f"[WARN] Dossier '{folder}' non trouvé, ignoré.")
                    continue
                imgs = _get_images_in_folder(folder)
                slide_images.extend(imgs)

            # Si Gemma a choisi des dossiers invalides → fallback random
            if not slide_images:
                print(f"[WARN] Slide '{slide.get('titre', '?')}' : aucune image, fallback random.")
                fallback_folder = random.choice(available_folders)
                slide_images    = _get_images_in_folder(fallback_folder)

            # Sélection aléatoire de 2-3 images dans le pool de la slide
            selected = random.sample(slide_images, min(3, len(slide_images)))

            # Construction du frame composite
            frame    = _build_slide_frame(selected)
            clip     = ImageClip(frame, duration=slide_duration)
            video_clips.append(clip)

            print(f"[INFO] Slide '{slide.get('titre', '?')}' : "
                  f"{len(selected)} image(s), {slide_duration:.1f}s")

        if not video_clips:
            return {"video_path": None, "error": "Aucun clip vidéo généré"}

        # ── 6. Export vidéo temporaire (sans audio) ───────────────────────────
        temp_video_path = os.path.join(TEMP_ROOT, f"temp_video_{get_random_name()}.mp4")
        final_clip = concatenate_videoclips(video_clips, method="compose")
        final_clip.write_videofile(
            temp_video_path,
            codec="libx264",
            fps=FPS,
            audio=False,
            logger=None
        )
        final_clip.close()

        # ── 7. Ajout des sous-titres ──────────────────────────────────────────
        subtitled_video_path = os.path.join(TEMP_ROOT, f"subtitled_{get_random_name()}.mp4")
        if segments:
            add_subtitles_to_video(temp_video_path, segments, subtitled_video_path)
        else:
            # Pas de sous-titres : on copie juste
            import shutil
            shutil.copy(temp_video_path, subtitled_video_path)

        if not os.path.exists(subtitled_video_path):
            return {"video_path": None, "error": "Échec de l'ajout des sous-titres"}

        # ── 8. Fusion vidéo + audio final ────────────────────────────────────
        final_filename  = (
            output_filename.replace('.mp3', '.mp4')
            if output_filename
            else f"tutorial_{get_random_name()}.mp4"
        )
        final_video_path = os.path.join(MEDIA_ROOT, final_filename)

        video_clip = VideoFileClip(subtitled_video_path)
        audio_clip = AudioFileClip(audio_path)
        video_clip = video_clip.set_duration(total_duration)
        merged     = video_clip.set_audio(audio_clip)
        merged.write_videofile(
            final_video_path,
            codec="libx264",
            audio_codec="aac",
            logger=None
        )
        video_clip.close()
        audio_clip.close()
        merged.close()

        print(f"[OK] Vidéo générée : {final_video_path}")

        # ── 9. Nettoyage des fichiers temporaires ────────────────────────────
        for temp_file in [audio_path, temp_video_path, subtitled_video_path]:
            if temp_file and os.path.exists(temp_file):
                os.remove(temp_file)

        return str(final_video_path), script

    except Exception as e:
        print(traceback.format_exc())
        # Nettoyage même en cas d'erreur
        for temp_file in [audio_path, temp_video_path, subtitled_video_path]:
            if temp_file and os.path.exists(temp_file):
                try:
                    os.remove(temp_file)
                except Exception:
                    pass
        return {
            "video_path": None,
            "error": f"Erreur lors de la création du tutoriel : {str(e)}"
        }