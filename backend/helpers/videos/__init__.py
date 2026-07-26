import whisper
import cv2
import os
import soundfile as sf
import traceback
import sys
import random
import string
from pathlib import Path

BASE_DIR   = Path(__file__).resolve().parent.parent
MEDIA_ROOT = os.path.join(BASE_DIR, 'media', 'videos')
AUDIO_ROOT = os.path.join(BASE_DIR, 'media', 'videos', 'audios')

sys.stdout.reconfigure(encoding='utf-8')


def get_random_name(nb=10):
    return "".join([random.choice(string.ascii_letters + string.digits) for _ in range(nb)])


def get_audio_duration(audio_path: str) -> float:
    """
    Retourne la durée en secondes d'un fichier audio (WAV, MP3, etc.)
    sans pydub — utilise soundfile ou ffprobe en fallback.
    """
    try:
        info = sf.info(audio_path)
        return info.duration
    except Exception:
        # Fallback ffprobe si soundfile ne supporte pas le format
        import subprocess
        try:
            result = subprocess.run(
                [
                    "ffprobe", "-v", "error",
                    "-show_entries", "format=duration",
                    "-of", "default=noprint_wrappers=1:nokey=1",
                    audio_path
                ],
                capture_output=True,
                text=True,
                timeout=15
            )
            return float(result.stdout.strip())
        except Exception as e:
            print(f"[WARN] Impossible de lire la durée audio : {e}")
            return 60.0  # Valeur par défaut


def extract_audio_from_video(
    video_path: str,
    audio_output_path: str = None
) -> str | None:
    """
    Extrait l'audio d'une vidéo MP4 via ffmpeg directement (sans pydub).
    """
    if audio_output_path is None:
        audio_output_path = os.path.join(AUDIO_ROOT, "temp_audio.wav")

    try:
        import subprocess
        os.makedirs(os.path.dirname(audio_output_path), exist_ok=True)

        subprocess.run(
            [
                "ffmpeg", "-y",
                "-i", video_path,
                "-vn",
                "-acodec", "pcm_s16le",
                "-ar", "16000",
                "-ac", "1",
                audio_output_path
            ],
            capture_output=True,
            check=True,
            timeout=120
        )
        print(f"Audio extrait avec succès : {audio_output_path}")
        return audio_output_path

    except Exception as e:
        print(f"Erreur lors de l'extraction de l'audio : {str(e)}")
        print(traceback.format_exc())
        return None


def voice_to_text(audio_file: str, model_size: str = "medium", language: str = "fr") -> str | None:
    try:
        model  = whisper.load_model(model_size)
        print(f"Modèle {model_size} chargé avec succès.")
        result = model.transcribe(audio_file, language=language)
        return result["text"]
    except Exception as e:
        print(f"Erreur lors de la transcription avec Whisper : {str(e)}")
        print(traceback.format_exc())
        return None


def voice_to_text_with_timestamps(
    audio_file: str,
    model_size: str = "medium",
    language: str = "fr"
) -> list[dict] | None:
    try:
        model  = whisper.load_model(model_size)
        print(f"Modèle {model_size} chargé avec succès.")
        result = model.transcribe(audio_file, language=language, verbose=False)
        print("Transcription avec horodatages terminée.")
        return result["segments"]
    except Exception as e:
        print(f"Erreur lors de la transcription avec Whisper : {str(e)}")
        print(traceback.format_exc())
        return None


def add_subtitles_to_video(
    video_path: str,
    segments: list[dict],
    output_video_path: str = None
) -> str | None:
    if output_video_path is None:
        output_video_path = os.path.join(
            MEDIA_ROOT,
            f"output_with_subtitles_{get_random_name()}.mp4"
        )
    try:
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            raise Exception("Impossible d'ouvrir la vidéo.")

        fps    = cap.get(cv2.CAP_PROP_FPS)
        width  = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out    = cv2.VideoWriter(output_video_path, fourcc, fps, (width, height))

        frame_count = 0
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            current_time  = frame_count / fps
            subtitle_text = ""

            for segment in segments:
                if segment["start"] <= current_time <= segment["end"]:
                    subtitle_text = segment["text"]
                    break

            if subtitle_text:
                font           = cv2.FONT_HERSHEY_SIMPLEX
                font_scale     = 0.35
                font_thickness = 1
                max_width      = width - 40

                words        = subtitle_text.split()
                lines        = []
                current_line = ""

                for word in words:
                    test_line = f"{current_line} {word}".strip() if current_line else word
                    text_size = cv2.getTextSize(test_line, font, font_scale, font_thickness)[0]
                    if text_size[0] <= max_width:
                        current_line = test_line
                    else:
                        lines.append(current_line)
                        current_line = word
                if current_line:
                    lines.append(current_line)

                line_height  = 10
                text_y_base  = height - 10

                for i, line in enumerate(reversed(lines)):
                    text_size = cv2.getTextSize(line, font, font_scale, font_thickness)[0]
                    text_x    = (width - text_size[0]) // 2
                    text_y    = text_y_base - i * line_height
                    if text_y > 0:
                        cv2.putText(
                            frame, line, (text_x, text_y),
                            font, font_scale, (0, 0, 0),
                            font_thickness + 1, cv2.LINE_AA
                        )
                        cv2.putText(
                            frame, line, (text_x, text_y),
                            font, font_scale, (255, 255, 255),
                            font_thickness, cv2.LINE_AA
                        )

            out.write(frame)
            frame_count += 1

        cap.release()
        out.release()
        cv2.destroyAllWindows()
        print(f"Vidéo avec sous-titres sauvegardée : {output_video_path}")
        return output_video_path

    except Exception as e:
        print(f"Erreur lors de l'ajout des sous-titres : {str(e)}")
        print(traceback.format_exc())
        return None


def video_to_subtitled_video(
    video_path: str,
    output_video_path: str = None
) -> tuple[str, str] | None:
    if output_video_path is None:
        output_video_path = os.path.join(
            MEDIA_ROOT,
            f"output_with_subtitles_{get_random_name()}.mp4"
        )
    try:
        audio_file = extract_audio_from_video(video_path)
        if not audio_file:
            return None

        segments = voice_to_text_with_timestamps(audio_file)
        if not segments:
            return None

        add_subtitles_to_video(video_path, segments, output_video_path)
        content_file = voice_to_text(audio_file)

        if os.path.exists(audio_file):
            os.remove(audio_file)
            print(f"Fichier temporaire supprimé : {audio_file}")

        return output_video_path, content_file

    except Exception as e:
        print(f"Erreur générale : {str(e)}")
        print(traceback.format_exc())
        return None
