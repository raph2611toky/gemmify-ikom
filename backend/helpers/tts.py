from transformers import VitsModel, AutoTokenizer
import torch
import scipy.io.wavfile
import traceback
import os

_MODEL_NAME = "facebook/mms-tts-mlg"
_model = VitsModel.from_pretrained(_MODEL_NAME)
_tokenizer = AutoTokenizer.from_pretrained(_MODEL_NAME)


def simple_tts_malagasy(text: str, output_path: str = "output.wav") -> str:
    if not text:
        return "Texte requis"
    try:
        inputs = _tokenizer(text, return_tensors="pt")

        with torch.no_grad():
            output = _model(**inputs).waveform

        sample_rate = _model.config.sampling_rate
        waveform = output.squeeze().cpu().numpy()

        scipy.io.wavfile.write(output_path, rate=sample_rate, data=waveform)

        return output_path
    except Exception as e:
        print(traceback.format_exc())
        return f"Erreur lors de la génération audio: {str(e)}"


if __name__ == "__main__":
    path = simple_tts_malagasy("Manao ahoana ianao, tsara fa misaotra")
    print(f"Audio généré: {path}")