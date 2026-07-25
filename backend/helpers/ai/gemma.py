from openai import OpenAI
from dotenv import load_dotenv
import os
import traceback

load_dotenv()
GOOGLE_API_KEY_AI = os.getenv("GOOGLE_API_KEY_AI")

client = OpenAI(
    api_key=GOOGLE_API_KEY_AI,
    base_url="https://generativelanguage.googleapis.com/v1beta/openai/"
)

def simple_chat_gemma(message: str) -> str:
    if not message:
        return "Message requis"
    try:
        response = client.chat.completions.create(
            model="gemma-4-31b-it",
            messages=[
                {"role": "user", "content": f"{message}"}
            ]
        )
        return response.choices[0].message.content
    except Exception as e:
        print(traceback.format_exc())
        return f"Erreur lors de la communication avec l'IA: {str(e)}"