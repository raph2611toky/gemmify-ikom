# helpers/tts.py
from transformers import VitsModel, AutoTokenizer
import torch
import scipy.io.wavfile
import traceback
import os
import re

_MODEL_NAME = "facebook/mms-tts-mlg"

print(f"[TTS] Chargement du modèle {_MODEL_NAME}...")
_model     = VitsModel.from_pretrained(_MODEL_NAME)
_tokenizer = AutoTokenizer.from_pretrained(_MODEL_NAME)
_model.eval()
print(f"[TTS] Modèle chargé.")


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
                words   = sentence.split()
                sub     = ""
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

    return chunks


def simple_tts_malagasy(text: str, output_path: str = "output.wav") -> str:
    if not text or not text.strip():
        return "Texte requis"

    try:
        import numpy as np
        import scipy.io.wavfile

        sample_rate = _model.config.sampling_rate
        chunks      = _split_text_into_chunks(text.strip())

        print(f"[TTS] {len(chunks)} chunk(s) à synthétiser.")

        all_waveforms = []

        for i, chunk in enumerate(chunks, start=1):
            print(f"[TTS] Chunk {i}/{len(chunks)} : '{chunk[:60]}...' " if len(chunk) > 60 else f"[TTS] Chunk {i}/{len(chunks)} : '{chunk}'")

            inputs = _tokenizer(chunk, return_tensors="pt")

            with torch.no_grad():
                output = _model(**inputs).waveform

            waveform = output.squeeze().cpu().numpy()
            all_waveforms.append(waveform)

            if i < len(chunks):
                silence = np.zeros(int(sample_rate * 0.3), dtype=waveform.dtype)
                all_waveforms.append(silence)

        final_waveform = np.concatenate(all_waveforms)

        max_val = np.max(np.abs(final_waveform))
        if max_val > 0:
            final_waveform = final_waveform / max_val * 0.95

        final_int16 = (final_waveform * 32767).astype(np.int16)

        scipy.io.wavfile.write(output_path, rate=sample_rate, data=final_int16)
        print(f"[TTS] Audio généré : {output_path} ({len(final_waveform) / sample_rate:.1f}s)")

        return output_path

    except Exception as e:
        print(traceback.format_exc())
        return f"Erreur lors de la génération audio: {str(e)}"