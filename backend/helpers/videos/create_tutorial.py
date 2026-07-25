from helpers.videos import add_subtitles_to_video, get_random_name, voice_to_text_with_timestamps
from helpers.evenlabs import text_to_speech, voices, text_to_speech_with_timestamps
from helpers.ai.gemma import simple_chat
from pydub import AudioSegment
from moviepy.editor import VideoFileClip, AudioFileClip, ImageClip, concatenate_videoclips
from pathlib import Path
import numpy as np
import random
import cv2
import os
from enum import Enum

BASE_DIR = Path(__file__).resolve().parent.parent.parent
MEDIA_ROOT = os.path.join(BASE_DIR, 'media', 'tutorials')
TEMP_ROOT = os.path.join(BASE_DIR, 'media', 'temp')
IMAGE_ROOT = os.path.join(BASE_DIR, 'helpers', 'services', 'images')

class TutorialType(Enum):
    MOT_DE_PASSE_SECURISE = "MOT_DE_PASSE_SECURISE"
    ALGORITHME = "ALGORITHME"

def create_child_friendly_tutorial(tutoriel_description, tutorial_type, sexe='MASCULIN', max_duration=60, output_filename=None):
    audio_path = None
    temp_video_path = None
    subtitled_video_path = None
    try:
        os.makedirs(MEDIA_ROOT, exist_ok=True)
        os.makedirs(TEMP_ROOT, exist_ok=True)

        topic_mapping = {
            "Il faut sécuriser son mot de passe": {
                "type": TutorialType.MOT_DE_PASSE_SECURISE,
                "folders": ['mot_de_passe', 'mot_de_passe/forts', 'coffre-fort', 'parents', 'enfants/filles', 'enfants/garcons', 'enfants/groupes'],
            },
            "Cuire un œuf": {
                "type": TutorialType.ALGORITHME,
                "folders": ['oeufs', 'cuir_oeufs', 'la_poile', 'feux', 'cuisine', 'enfants/filles', 'enfants/garcons', 'enfants/groupes', 'parents'],
            },
            "Aller à l’école": {
                "type": TutorialType.ALGORITHME,
                "folders": ['ecoles', 'bus', 'cartables', 'fournitures', 'enfants/filles', 'enfants/garcons', 'enfants/groupes'],
            }
        }

        if tutoriel_description not in topic_mapping:
            return {"video_path": None, "error": f"Tutoriel non supporté: {tutoriel_description}"}

        topic_config = topic_mapping[tutoriel_description]
        if topic_config["type"] != tutorial_type:
            return {"video_path": None, "error": f"Type de tutoriel incorrect pour {tutoriel_description}"}

        prompt = (
            f"Explique directement le concept suivant aux enfants de 8 à 12 ans en 1 minute maximum, "
            f"sans répéter le contexte, en utilisant un langage clair, amusant et engageant : '{tutoriel_description}'. "
            f"Concentre-toi sur une explication simple avec des exemples de la vie quotidienne. "
            f"Le texte doit être court (environ 100-150 mots) et adapté à une lecture orale."
        )
        adapted_text = simple_chat(prompt)
        if "Erreur" in adapted_text:
            return {"video_path": None, "error": adapted_text}

        voice_id = random.choice(voices[sexe[0].upper()])
        audio_filename = f"audio_{get_random_name()}.mp3" if not output_filename else output_filename
        audio_path, _ = text_to_speech(text=adapted_text, sexe=sexe, output_filename=audio_filename)
        if not audio_path:
            return {"video_path": None, "error": "Échec de la génération audio"}

        timestamp_data = text_to_speech_with_timestamps(voice_id, adapted_text)
        if not timestamp_data:
            return {"video_path": None, "error": "Échec de la génération des timestamps"}

        alignment = timestamp_data.get("alignment", {})
        chars = alignment.get("chars", [])
        start_times = alignment.get("charStartTimesMs", [])
        durations = alignment.get("charDurationsMs", [])

        if not (chars and start_times and durations and len(chars) == len(start_times) == len(durations)):
            print("Warning: Invalid timestamp structure from ElevenLabs. Falling back to Whisper.")
            segments = voice_to_text_with_timestamps(audio_path)
            if not segments:
                return {"video_path": None, "error": "Échec de la génération des timestamps via Whisper"}
        else:
            segments = []
            current_text = ""
            current_start = None
            for i, (char, start_ms, duration_ms) in enumerate(zip(chars, start_times, durations)):
                if current_start is None:
                    current_start = start_ms / 1000.0
                current_text += char
                if char == " " or len(current_text) > 20 or i == len(chars) - 1:
                    segments.append({
                        "start": current_start,
                        "end": (start_ms + duration_ms) / 1000.0,
                        "text": current_text.strip()
                    })
                    current_text = ""
                    current_start = None

        image_pool = []
        for folder in topic_config["folders"]:
            folder_path = os.path.join(IMAGE_ROOT, folder)
            if os.path.exists(folder_path):
                image_pool.extend([os.path.join(folder_path, f) for f in os.listdir(folder_path) if f.endswith('.png')])

        if len(image_pool) < 4: 
            return {"video_path": None, "error": "Pas assez d'images dans le pool (minimum 4 requis)"}

        frame_width, frame_height = 1280, 720
        fps = 30
        audio_duration = AudioSegment.from_file(audio_path).duration_seconds
        total_duration = min(max_duration, audio_duration)
        slide_duration = 15 
        num_slides = max(2, int(total_duration // slide_duration))

        video_clips = []
        used_images = set()
        for slide_idx in range(num_slides):
            topic_folders = [f for f in topic_config["folders"] if not f.startswith('enfants') and f != 'parents' and f != 'cuisine']
            topic_images = [img for img in image_pool if any(f in img for f in topic_folders) and img not in used_images]
            other_images = [img for img in image_pool if img not in topic_images and img not in used_images]
            
            num_images = random.randint(2, 4)
            slide_images = random.sample(topic_images, min(2, len(topic_images))) if topic_images else []
            remaining_slots = num_images - len(slide_images)
            if remaining_slots > 0 and other_images:
                slide_images.extend(random.sample(other_images, min(remaining_slots, len(other_images))))
            
            if not slide_images:
                return {"video_path": None, "error": f"Échec de la sélection d'images pour la diapositive {slide_idx + 1}"}

            composite = np.ones((frame_height, frame_width, 3), dtype=np.uint8) * 255
            grid_cols = min(num_images, 2) 
            grid_rows = (num_images + 1) // 2
            img_width = frame_width // grid_cols
            img_height = frame_height // grid_rows

            for i, img_path in enumerate(slide_images):
                img = cv2.imread(img_path, cv2.IMREAD_UNCHANGED) 
                if img is None:
                    continue
                if img.shape[2] == 4:
                    alpha = img[:, :, 3] / 255.0
                    img_rgb = img[:, :, :3]
                else:
                    alpha = np.any(img != [0, 0, 0], axis=2).astype(np.float32)
                    img_rgb = img

                img_h, img_w = img_rgb.shape[:2]
                aspect_ratio = img_w / img_h
                target_width = img_width - 20
                target_height = img_height - 20
                if aspect_ratio > (target_width / target_height):
                    new_width = target_width
                    new_height = int(new_width / aspect_ratio)
                else:
                    new_height = target_height
                    new_width = int(new_height * aspect_ratio)
                
                img_resized = cv2.resize(img_rgb, (new_width, new_height), interpolation=cv2.INTER_AREA)
                if img.shape[2] == 4:
                    alpha_resized = cv2.resize(alpha, (new_width, new_height), interpolation=cv2.INTER_AREA)
                else:
                    alpha_resized = cv2.resize(alpha, (new_width, new_height), interpolation=cv2.INTER_AREA)

                row = i // grid_cols
                col = i % grid_cols
                x = col * img_width + (img_width - new_width) // 2
                y = row * img_height + (img_height - new_height) // 2

                for c in range(3):
                    composite[y:y+new_height, x:x+new_width, c] = composite[y:y+new_height, x:x+new_width, c] * (1 - alpha_resized) + img_resized[:, :, c] * alpha_resized

                used_images.add(img_path)

            composite = cv2.cvtColor(composite, cv2.COLOR_BGR2RGB)
            clip = ImageClip(composite, duration=min(slide_duration, total_duration - slide_idx * slide_duration))
            video_clips.append(clip)

        temp_video_path = os.path.join(TEMP_ROOT, f"temp_video_{get_random_name()}.mp4")
        final_clip = concatenate_videoclips(video_clips)
        final_clip.write_videofile(temp_video_path, codec="libx264", fps=fps, audio=False)

        subtitled_video_filename = f"temp_subtitled_{get_random_name()}.mp4"
        subtitled_video_path = os.path.join(TEMP_ROOT, subtitled_video_filename)
        add_subtitles_to_video(temp_video_path, segments, subtitled_video_path)
        if not os.path.exists(subtitled_video_path):
            return {"video_path": None, "error": "Échec de l'ajout des sous-titres"}

        final_video_filename = f"tutorial_{get_random_name()}.mp4" if not output_filename else output_filename.replace('.mp3', '.mp4')
        final_video_path = os.path.join(MEDIA_ROOT, final_video_filename)

        video_clip = VideoFileClip(subtitled_video_path)
        audio_clip = AudioFileClip(audio_path)
        video_clip = video_clip.set_duration(total_duration)
        final_clip = video_clip.set_audio(audio_clip)
        final_clip.write_videofile(final_video_path, codec="libx264", audio_codec="aac")
        video_clip.close()
        audio_clip.close()
        final_clip.close()

        for temp_file in [audio_path, temp_video_path, subtitled_video_path]:
            if temp_file and os.path.exists(temp_file):
                os.remove(temp_file)

        return str(final_video_path), adapted_text

    except Exception as e:
        for temp_file in [audio_path, temp_video_path, subtitled_video_path]:
            if temp_file and os.path.exists(temp_file):
                os.remove(temp_file)
        return {
            "video_path": None,
            "error": f"Erreur lors de la création du tutoriel: {str(e)}"
        }