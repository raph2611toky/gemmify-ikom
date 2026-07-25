from dotenv import load_dotenv
import os
import requests
import websocket
import json, random
from datetime import datetime
from pathlib import Path

load_dotenv()
API_KEY = os.getenv('EVENLABS_API_KEY')
EVENLABS_BASE_URL = "https://api.elevenlabs.io/v1"
BASE_DIR = Path(__file__).resolve().parent.parent
MEDIA_ROOT = os.path.join(BASE_DIR, 'media', 'elevenlabs', 'audio')

voices = {
    "F":['EXAVITQu4vr4xnSDxMaL','9BWtsMINqrJLrRacOk9x','FGY2WhTYpPnrIDTdsKH5','XB0fDUnXU5powFXDhCwa','Xb7hH8MSUJpSbSDYk0k2','XrExE9yKIg1WjnnlVkGX','cgSgspJ2msm6clMCkdW9','pFZP5JQG7iQjIQuC4Bku'],
    "M":['IKne3meq5aSn9XLyUdCD','JBFqnCBsd6RMkjVDRZzb','N2lVS1w4EtoT3dr4eOWO','bIHbv24MWmeRgasZH58o', 'cjVigY5qzO86Huf0OWal', 'iP95p4xoKVk53GoZ742B', 'onwK4e9ZLuTAKqWW03F9', 'pqHfZKP75CvOlQylNhV4']
}

def ensure_media_directory():
    """Ensure the media/elevenlabs/audio directory exists."""
    os.makedirs(MEDIA_ROOT, exist_ok=True)

def text_to_speech( text, sexe='FEMININ', model_id="eleven_multilingual_v2", output_format="mp3_44100_128", output_filename=None, **kwargs):
    ensure_media_directory()
    sexe = sexe[0].upper()
    voice_id = random.choice(voices[sexe])
    url = f"{EVENLABS_BASE_URL}/text-to-speech/{voice_id}"
    headers = {"xi-api-key": API_KEY, "Content-Type": "application/json"}
    data = {"text": text, "model_id": model_id, "output_format": output_format, **kwargs}
    
    response = requests.post(url, headers=headers, json=data)
    if response.status_code != 200:
        raise Exception(f"Erreur: {response.status_code}, {response.text}")

    # Generate unique filename if not provided
    if not output_filename:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_filename = f"audio_{kwargs.get('endpage_id', 'unknown')}_{timestamp}.mp3"
    
    output_path = os.path.join(f'{BASE_DIR}/media/elevenlabs/audio', output_filename)
    with open(output_path, 'wb') as f:
        f.write(response.content)
    
    return output_path, response.content

def text_to_speech_with_timestamps(voice_id, text, model_id="eleven_multilingual_v2", **kwargs):
    url = f"{EVENLABS_BASE_URL}/text-to-speech/{voice_id}/with-timestamps"
    headers = {"xi-api-key": API_KEY, "Content-Type": "application/json"}
    data = {"text": text, "model_id": model_id, **kwargs}
    response = requests.post(url, headers=headers, json=data)
    if response.status_code == 200:
        return response.json()
    else:
        raise Exception(f"Erreur: {response.status_code}, {response.text}")

def stream_speech(voice_id, text, model_id="eleven_multilingual_v2", output_format="mp3_44100_128", **kwargs):
    url = f"{EVENLABS_BASE_URL}/text-to-speech/{voice_id}/stream"
    headers = {"xi-api-key": API_KEY, "Content-Type": "application/json"}
    data = {"text": text, "model_id": model_id, "output_format": output_format, **kwargs}
    response = requests.post(url, headers=headers, json=data, stream=True)
    if response.status_code == 200:
        for chunk in response.iter_content(chunk_size=1024):
            if chunk:
                yield chunk
    else:
        raise Exception(f"Erreur: {response.status_code}, {response.text}")

def stream_speech_with_timestamps(voice_id, text, model_id="eleven_multilingual_v2", output_format="mp3_44100_128", **kwargs):
    url = f"{EVENLABS_BASE_URL}/text-to-speech/{voice_id}/stream/with-timestamps"
    headers = {"xi-api-key": API_KEY, "Content-Type": "application/json"}
    data = {"text": text, "model_id": model_id, "output_format": output_format, **kwargs}
    response = requests.post(url, headers=headers, json=data, stream=True)
    if response.status_code == 200:
        for chunk in response.iter_content(chunk_size=1024):
            if chunk:
                yield json.loads(chunk.decode('utf-8'))
    else:
        raise Exception(f"Erreur: {response.status_code}, {response.text}")

def get_models():
    url = f"{EVENLABS_BASE_URL}/models"
    headers = {"xi-api-key": API_KEY}
    response = requests.get(url, headers=headers)
    if response.status_code == 200:
        return response.json()
    else:
        raise Exception(f"Erreur: {response.status_code}, {response.text}")

def stream_input(voice_id, text, model_id="eleven_multilingual_v2", **kwargs):
    def on_message(ws, message):
        data = json.loads(message)
        if "audio" in data:
            print("Morceau d'audio reçu:", data["audio"])
        if "alignment" in data:
            print("Données d'alignement reçues:", data["alignment"])

    def on_error(ws, error):
        print(f"Erreur WebSocket: {error}")

    def on_close(ws, close_status_code, close_msg):
        print("Connexion WebSocket fermée")

    def on_open(ws):
        init_message = {
            "text": " ",
            "voice_settings": kwargs.get("voice_settings", {"stability": 0.5, "similarity_boost": 0.8, "speed": 1})
        }
        ws.send(json.dumps(init_message))

        text_message = {"text": text, "try_trigger_generation": True}
        ws.send(json.dumps(text_message))

        close_message = {"text": ""}
        ws.send(json.dumps(close_message))

    url = f"wss://api.elevenlabs.io/v1/text-to-speech/{voice_id}/stream-input?model_id={model_id}"
    ws = websocket.WebSocketApp(url, on_message=on_message, on_error=on_error, on_close=on_close)
    ws.on_open = on_open
    ws.run_forever()

def list_voices():
    url = "https://api.elevenlabs.io/v1/voices"
    headers = {"xi-api-key": API_KEY}
    response = requests.get(url, headers=headers)
    if response.status_code == 200:
        data = response.json()
        for voice in data.get("voices", []):
            print(f"{voice['name']} → {voice['voice_id']}")
        return data["voices"]
    else:
        raise Exception(f"Erreur {response.status_code}: {response.text}")