from helpers.videos import (
    add_subtitles_to_video,
    get_random_name,
    get_audio_duration,
    voice_to_text_with_timestamps
)
from helpers.tts import simple_tts_malagasy
from helpers.ai.gemma.constante import GEMMA_TUTORIAL_SYSTEM_PROMPT
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
import shutil

load_dotenv()

try:
    from moviepy import VideoFileClip, AudioFileClip, ImageClip, concatenate_videoclips
    MOVIEPY_V2 = True
    print("[INFO] MoviePy 2.x détecté.")
except ImportError:
    from moviepy import VideoFileClip, AudioFileClip, ImageClip, concatenate_videoclips
    MOVIEPY_V2 = False
    print("[INFO] MoviePy 1.x détecté.")


def _set_duration(clip, duration):
    return clip.with_duration(duration) if MOVIEPY_V2 else clip.set_duration(duration)


def _set_audio(clip, audio):
    return clip.with_audio(audio) if MOVIEPY_V2 else clip.set_audio(audio)


BASE_DIR      = Path(__file__).resolve().parent.parent.parent
MEDIA_ROOT    = os.path.join(BASE_DIR, 'media', 'tutorials')
TEMP_ROOT     = os.path.join(BASE_DIR, 'media', 'temp')
DATASETS_ROOT = os.path.join(BASE_DIR, 'helpers', 'videos', 'datasets', 'images')

client = OpenAI(
    api_key=os.getenv("GOOGLE_API_KEY_AI_VIDEO_GENERATOR"),
    base_url="https://generativelanguage.googleapis.com/v1beta/openai/"
)

FRAME_WIDTH  = 1280
FRAME_HEIGHT = 720
FPS          = 30


def _get_available_folders() -> list[str]:
    folders = []
    for root, dirs, files in os.walk(DATASETS_ROOT):
        if any(f.endswith('.png') for f in files):
            rel = os.path.relpath(root, DATASETS_ROOT)
            folders.append(rel)
    return sorted(folders)


def _get_images_in_folder(folder_rel: str) -> list[str]:
    folder_abs = os.path.join(DATASETS_ROOT, folder_rel)
    if not os.path.exists(folder_abs):
        return []
    return [
        os.path.join(folder_abs, f)
        for f in os.listdir(folder_abs)
        if f.endswith('.png')
    ]


def _clean_json_response(raw: str) -> str:
    raw = raw.strip()
    raw = re.sub(r'<thought>.*?</thought>', '', raw, flags=re.DOTALL)
    raw = re.sub(r'^```(?:json)?\s*', '', raw.strip())
    raw = re.sub(r'\s*```$', '', raw.strip())
    raw = raw.strip()
    start = raw.find('{')
    end = raw.rfind('}')
    if start != -1 and end != -1 and end > start:
        raw = raw[start:end + 1]
    return raw.strip()


def _ask_gemma_for_tutorial_plan(sujet: str, folders: list[str]) -> dict | None:
    folders_str   = "\n".join(f"- {f}" for f in folders)
    system_prompt = GEMMA_TUTORIAL_SYSTEM_PROMPT.replace(
        "{folders_disponibles}", folders_str
    )

    raw = ""
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
                        f"'{sujet}'.\n"
                        f"IMPORTANT : le champ 'script' doit être rédigé EN MALAGASY "
                        f"(langue malgache), car il sera lu par un moteur TTS malagasy.\n"
                        f"Réponds UNIQUEMENT avec l'objet JSON final, sans balise <thought>, "
                        f"sans raisonnement visible, sans texte avant ou après le JSON."
                    )
                }
            ]
        )

        raw     = response.choices[0].message.content
        cleaned = _clean_json_response(raw)
        return json.loads(cleaned)

    except json.JSONDecodeError as e:
        print(f"[ERREUR JSON] Réponse Gemma invalide : {e}")
        print(f"[ERREUR JSON] Réponse brute : {raw}")
        return None
    except Exception:
        print(traceback.format_exc())
        return None


def _generate_malagasy_audio(script: str, output_dir: str) -> str | None:
    audio_filename = f"audio_{get_random_name()}.wav"
    audio_path     = os.path.join(output_dir, audio_filename)

    result = simple_tts_malagasy(text=script, output_path=audio_path)

    if not result:
        print("[ERREUR TTS] Résultat vide.")
        return None

    if result.startswith("Erreur") or result.startswith("Texte"):
        print(f"[ERREUR TTS] {result}")
        return None

    if not os.path.exists(result):
        print(f"[ERREUR TTS] Fichier introuvable : {result}")
        return None

    size_kb = os.path.getsize(result) // 1024
    print(f"[TTS] Audio WAV généré : {result} ({size_kb} KB)")
    return result


def _build_whisper_segments(audio_path: str) -> list[dict]:
    print("[INFO] Génération des sous-titres via Whisper (mg)...")
    segments = voice_to_text_with_timestamps(audio_path, language="mg")
    if not segments:
        print("[WARN] Whisper n'a pas retourné de segments.")
        return []
    print(f"[INFO] {len(segments)} segment(s) de sous-titres générés.")
    return segments


def _build_slide_frame(image_paths: list[str]) -> np.ndarray:
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
            print(f"[WARN] Image illisible : {img_path}")
            continue

        if img.ndim == 3 and img.shape[2] == 4:
            alpha   = img[:, :, 3] / 255.0
            img_rgb = img[:, :, :3]
        elif img.ndim == 2:
            alpha   = np.ones(img.shape[:2], dtype=np.float32)
            img_rgb = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
        else:
            alpha   = np.ones(img.shape[:2], dtype=np.float32)
            img_rgb = img

        src_h, src_w = img_rgb.shape[:2]
        if src_h == 0 or src_w == 0:
            continue

        target_w = max(img_w - 20, 1)
        target_h = max(img_h - 20, 1)
        ratio    = min(target_w / src_w, target_h / src_h)
        new_w    = max(int(src_w * ratio), 1)
        new_h    = max(int(src_h * ratio), 1)

        img_resized   = cv2.resize(img_rgb, (new_w, new_h), interpolation=cv2.INTER_AREA)
        alpha_resized = cv2.resize(alpha,   (new_w, new_h), interpolation=cv2.INTER_AREA)

        row   = i // grid_cols
        col   = i % grid_cols
        x     = col * img_w + (img_w - new_w) // 2
        y     = row * img_h + (img_h - new_h) // 2
        x_end = min(x + new_w, FRAME_WIDTH)
        y_end = min(y + new_h, FRAME_HEIGHT)
        pw    = x_end - x
        ph    = y_end - y

        if pw <= 0 or ph <= 0:
            continue

        img_resized   = img_resized[:ph, :pw]
        alpha_resized = alpha_resized[:ph, :pw]

        for c in range(3):
            composite[y:y_end, x:x_end, c] = (
                composite[y:y_end, x:x_end, c] * (1 - alpha_resized)
                + img_resized[:, :, c] * alpha_resized
            ).astype(np.uint8)

    return cv2.cvtColor(composite, cv2.COLOR_BGR2RGB)


def _build_white_frame() -> np.ndarray:
    return np.ones((FRAME_HEIGHT, FRAME_WIDTH, 3), dtype=np.uint8) * 255


def create_dynamic_tutorial(
    sujet: str,
    sexe: str = 'MASCULIN',
    max_duration: int = 60,
    output_filename: str | None = None
) -> tuple[str, str] | dict:

    audio_path           = None
    temp_video_path      = None
    subtitled_video_path = None

    try:
        os.makedirs(MEDIA_ROOT, exist_ok=True)
        os.makedirs(TEMP_ROOT,  exist_ok=True)

        available_folders = _get_available_folders()
        if not available_folders:
            return {
                "video_path": None,
                "error": "Aucun dossier d'images trouvé dans datasets/"
            }
        print(f"[INFO] {len(available_folders)} dossiers d'images disponibles.")

        print(f"[INFO] Génération du plan pour : '{sujet}'")
        plan = _ask_gemma_for_tutorial_plan(sujet, available_folders)

        if not plan:
            return {
                "video_path": None,
                "error": "Échec de la génération du plan par Gemma"
            }

        script = plan.get("script", "").strip()
        slides = plan.get("slides", [])

        if not script:
            return {"video_path": None, "error": "Script vide généré par Gemma"}
        if not slides:
            return {"video_path": None, "error": "Aucune slide générée par Gemma"}

        print(f"[INFO] Script ({len(script.split())} mots), {len(slides)} slides.")
        print(f"[INFO] Aperçu script : {script[:120]}...")

        print("[INFO] Synthèse vocale malagasy en cours...")
        audio_path = _generate_malagasy_audio(script, TEMP_ROOT)

        if not audio_path:
            return {
                "video_path": None,
                "error": "Échec de la génération audio TTS malagasy"
            }

        audio_duration = get_audio_duration(audio_path)
        total_duration = min(float(max_duration), audio_duration)
        print(f"[INFO] Audio : {audio_duration:.1f}s → vidéo : {total_duration:.1f}s")

        segments = _build_whisper_segments(audio_path)

        total_slides_duration = sum(
            max(s.get("duree_secondes", 10), 1) for s in slides
        )

        video_clips = []

        for idx, slide in enumerate(slides):
            titre              = slide.get("titre", f"Slide {idx + 1}")
            slide_folders      = slide.get("dossiers_images", [])
            slide_duration_raw = max(slide.get("duree_secondes", 10), 1)

            slide_duration = (slide_duration_raw / total_slides_duration) * total_duration
            slide_duration = max(slide_duration, 1.0)

            slide_images = []
            for folder in slide_folders:
                if folder not in available_folders:
                    print(f"[WARN] Slide '{titre}' : dossier '{folder}' invalide, ignoré.")
                    continue
                imgs = _get_images_in_folder(folder)
                slide_images.extend(imgs)

            if not slide_images:
                fallback = random.choice(available_folders)
                print(f"[WARN] Slide '{titre}' → fallback dossier : '{fallback}'")
                slide_images = _get_images_in_folder(fallback)

            if slide_images:
                selected = random.sample(slide_images, min(3, len(slide_images)))
                frame    = _build_slide_frame(selected)
                print(
                    f"[INFO] Slide '{titre}' : "
                    f"{len(selected)} image(s), {slide_duration:.1f}s"
                )
            else:
                frame = _build_white_frame()
                print(f"[WARN] Slide '{titre}' : frame blanche, {slide_duration:.1f}s")

            clip = ImageClip(frame, duration=slide_duration)
            video_clips.append(clip)

        if not video_clips:
            return {"video_path": None, "error": "Aucun clip vidéo généré"}

        temp_video_path = os.path.join(
            TEMP_ROOT, f"temp_video_{get_random_name()}.mp4"
        )
        print(f"[INFO] Assemblage de {len(video_clips)} clip(s)...")
        assembled = concatenate_videoclips(video_clips, method="compose")
        assembled.write_videofile(
            temp_video_path,
            codec="libx264",
            fps=FPS,
            audio=False,
            logger=None
        )
        assembled.close()
        for clip in video_clips:
            try:
                clip.close()
            except Exception:
                pass

        print(f"[INFO] Vidéo temporaire : {temp_video_path}")

        subtitled_video_path = os.path.join(
            TEMP_ROOT, f"subtitled_{get_random_name()}.mp4"
        )
        if segments:
            result_sub = add_subtitles_to_video(
                temp_video_path, segments, subtitled_video_path
            )
            if not result_sub or not os.path.exists(subtitled_video_path):
                print("[WARN] Échec sous-titres → copie sans sous-titres.")
                shutil.copy(temp_video_path, subtitled_video_path)
        else:
            print("[INFO] Pas de segments → copie sans sous-titres.")
            shutil.copy(temp_video_path, subtitled_video_path)

        if not os.path.exists(subtitled_video_path):
            return {
                "video_path": None,
                "error": "Fichier vidéo sous-titré introuvable"
            }

        final_filename = (
            output_filename
            .replace('.wav', '.mp4')
            .replace('.mp3', '.mp4')
            if output_filename
            else f"tutorial_{get_random_name()}.mp4"
        )
        final_video_path = os.path.join(MEDIA_ROOT, final_filename)

        print(f"[INFO] Fusion audio + vidéo → {final_video_path}")

        video_clip = VideoFileClip(subtitled_video_path)
        audio_clip = AudioFileClip(audio_path)

        video_clip = _set_duration(video_clip, total_duration)
        merged     = _set_audio(video_clip, audio_clip)

        merged.write_videofile(
            final_video_path,
            codec="libx264",
            audio_codec="aac",
            logger=None
        )
        video_clip.close()
        audio_clip.close()
        merged.close()

        print(f"[OK] Vidéo finale : {final_video_path}")

        for temp_file in [audio_path, temp_video_path, subtitled_video_path]:
            if temp_file and os.path.exists(temp_file):
                try:
                    os.remove(temp_file)
                    print(f"[CLEAN] Supprimé : {temp_file}")
                except Exception as e:
                    print(f"[WARN] Impossible de supprimer {temp_file} : {e}")

        return str(final_video_path), script

    except Exception as e:
        print(f"[ERREUR] create_dynamic_tutorial : {str(e)}")
        print(traceback.format_exc())

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
        
def decide_video_reuse(sujet: str, contexte: str, existing: list[dict]) -> dict:
    """
    Demande à Gemma si une vidéo déjà existante (même contexte) correspond
    assez précisément au nouveau sujet pour être réutilisée, plutôt que
    de régénérer une vidéo quasi identique.

    Retourne :
    {"action": "reutiliser_video", "video_id": <id>, "raison": "..."}
    ou
    {"action": "creer_video", "video_id": None, "raison": "..."}
    """
    if not existing:
        return {
            "action": "creer_video",
            "video_id": None,
            "raison": "Aucune vidéo existante pour ce contexte."
        }

    existing_str = "\n".join(
        f"- id={v['id']} | sujet=\"{v['sujet']}\"" for v in existing
    )

    system_prompt = (
        "Tu es un assistant qui décide si une vidéo pédagogique déjà existante "
        "correspond suffisamment à une nouvelle demande, pour éviter de régénérer "
        "un contenu quasi identique.\n\n"
        "Réponds UNIQUEMENT avec un objet JSON, sans texte autour, de la forme :\n"
        '{"action": "reutiliser_video", "video_id": <id>, "raison": "..."} '
        "si une vidéo existante correspond clairement au même sujet précis, ou\n"
        '{"action": "creer_video", "video_id": null, "raison": "..."} '
        "si aucune vidéo existante ne correspond d'assez près.\n"
        "Sois strict : ne réutilise que si le sujet précis est vraiment le même "
        "(pas seulement la même matière/contexte général)."
    )

    user_prompt = (
        f"Nouveau sujet demandé : \"{sujet}\"\n"
        f"Contexte : \"{contexte}\"\n\n"
        f"Vidéos déjà existantes pour ce contexte :\n{existing_str}\n\n"
        "Décide : réutiliser une vidéo existante ou en créer une nouvelle."
    )

    raw = ""
    try:
        response = client.chat.completions.create(
            model="gemma-4-31b-it",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ]
        )
        raw     = response.choices[0].message.content
        cleaned = _clean_json_response(raw)
        decision = json.loads(cleaned)

        if decision.get("action") not in ("reutiliser_video", "creer_video"):
            return {"action": "creer_video", "video_id": None, "raison": "Réponse IA invalide."}

        return decision

    except json.JSONDecodeError as e:
        print(f"[ERREUR JSON] Décision réutilisation invalide : {e}")
        print(f"[ERREUR JSON] Réponse brute : {raw}")
        return {"action": "creer_video", "video_id": None, "raison": "Erreur de parsing IA."}
    except Exception:
        print(traceback.format_exc())
        return {"action": "creer_video", "video_id": None, "raison": "Erreur IA."}