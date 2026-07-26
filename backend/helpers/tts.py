# helpers/tts.py

from transformers import VitsModel, AutoTokenizer
import torch
import scipy.io.wavfile
import traceback
import re
import os

_MODEL_NAME = "facebook/mms-tts-mlg"

print(f"[TTS] Chargement du modèle {_MODEL_NAME}...")
_model     = VitsModel.from_pretrained(_MODEL_NAME)
_tokenizer = AutoTokenizer.from_pretrained(_MODEL_NAME)
_model.eval()
print(f"[TTS] Modèle chargé.")

_SAMPLE_RATE = _model.config.sampling_rate


def _split_text_into_chunks(text: str, max_chars: int = 200) -> list[str]:
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    chunks    = []
    current   = ""

    for sentence in sentences:
        if len(current) + len(sentence) + 1 <= max_chars:
            current = f"{current} {sentence}".strip()
        else:
            if current:
                chunks.append(current)
            if len(sentence) > max_chars:
                words = sentence.split()
                sub   = ""
                for word in words:
                    if len(sub) + len(word) + 1 <= max_chars:
                        sub = f"{sub} {word}".strip()
                    else:
                        if sub:
                            chunks.append(sub)
                        sub = word
                if sub:
                    chunks.append(sub)
            else:
                current = sentence

    if current:
        chunks.append(current)

    if not chunks:
        chunks = [text.strip()]

    return chunks


def simple_tts_malagasy(text: str, output_path: str = "output.wav") -> str:
    if not text or not text.strip():
        return "Texte requis"

    try:
        import numpy as np

        chunks = _split_text_into_chunks(text.strip())
        print(f"[TTS] {len(chunks)} chunk(s) à synthétiser.")

        all_waveforms = []

        for i, chunk in enumerate(chunks, start=1):
            apercu = f"'{chunk[:60]}...'" if len(chunk) > 60 else f"'{chunk}'"
            print(f"[TTS] Chunk {i}/{len(chunks)} : {apercu}")

            inputs = _tokenizer(chunk, return_tensors="pt")

            with torch.no_grad():
                output = _model(**inputs).waveform

            waveform = output.squeeze().cpu().numpy()

            if waveform.ndim != 1:
                waveform = waveform.flatten()

            all_waveforms.append(waveform)

            if i < len(chunks):
                silence = np.zeros(int(_SAMPLE_RATE * 0.3), dtype=np.float32)
                all_waveforms.append(silence)

        final_waveform = np.concatenate(all_waveforms).astype(np.float32)

        max_val = np.max(np.abs(final_waveform))
        if max_val > 0:
            final_waveform = final_waveform / max_val * 0.95

        final_int16 = (final_waveform * 32767).astype(np.int16)

        output_dir = os.path.dirname(output_path)
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)

        scipy.io.wavfile.write(output_path, rate=_SAMPLE_RATE, data=final_int16)

        duration = len(final_waveform) / _SAMPLE_RATE
        size_kb  = os.path.getsize(output_path) // 1024
        print(f"[TTS] Audio généré : {output_path} ({duration:.1f}s, {size_kb} KB)")

        return output_path

    except Exception as e:
        print(traceback.format_exc())
        return f"Erreur lors de la génération audio: {str(e)}"
