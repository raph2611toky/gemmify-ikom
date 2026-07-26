"""
Conversion du dataset Mpanabe AI vers le nouveau schéma JSON de réponse.

Ancien format (dans chaque message assistant, en JSON stringifié) :
    {"reponse": "...", "action": "none"|"add_user_progression", "choix": ["...", "..."]}

Nouveau format cible :
    {
      "response": "Markdown complet et terminé, en malagasy",
      "action": "reponse_chat" | "add_cursus_content" | "generate_game",
      "choices": <dépend de action, voir ci-dessous>,
      "progress": {
        "save": bool,
        "skill_id": str,
        "skill_label": str,
        "evidence": str,
        "correct": bool | null,
        "score": int,
        "max_score": int,
        "understanding": int,
        "xp": int,
        "lesson_completed": bool
      },
      "memory_summary": "Résumé très court"
    }

    - action == "reponse_chat"       -> choices = [{"id","label","message"}, ...]
    - action == "add_cursus_content" -> choices = {"categorie","cursus_categorie","status"}
    - action == "generate_game"      -> choices = {"type": "quizz"|"memoire"|"defi_chrono"|"vraie_ou_faux", ...}
      (aucun exemple generate_game dans le corpus actuel -> à générer séparément)

Usage:
    python convert_schema.py mpanabe_train_kely.jsonl mpanabe_train_v2.jsonl
"""

import json
import re
import string
import sys
from typing import Any

NEW_SYSTEM_PROMPT = (
    "Ianao dia Mpanabe AI, mpampianatra nomerika malemy fanahy sy manam-paharetana ho an'ny "
    "mpianatra eto Madagasikara. Mampiasà teny malagasy mazava, ampifanaraho amin'ny "
    "ambaratongan'ny mpianatra ny fanazavana, ary hazavao tsikelikely amin'ny ohatra akaiky ny "
    "fiainana. Mametraha fanontaniana iray ihany isaky ny valiny. Aza manao ny asa manontolo ho "
    "solon'ny mpianatra fa tariho izy hahita ny valiny irery. Ny valinao dia tsy maintsy zavatra "
    "JSON manan-kery TANTERAKA misy ireto saha ireto ihany: response, action, choices, progress, "
    "memory_summary. Aza mamoaka teny hafa ivelan'io JSON io. Ny response dia tsy maintsy ho "
    "Markdown feno sy vita, latsaky ny 110 teny, ary teny malagasy. Raha 'reponse_chat' ny action "
    "dia lisitry ny safidy (id, label, message) ny choices. Raha 'add_cursus_content' dia rakitra "
    "misy categorie, cursus_categorie, status ny choices. Raha 'generate_game' dia rakitra misy "
    "type (quizz, memoire, defi_chrono, vraie_ou_faux) sy ny angona mifandraika amin'io ny choices."
)

# Mots-clés heuristiques pour détecter une réponse correcte/incorrecte en malagasy
CORRECT_HINTS = ["marina", "tsara", "mahay", "mety", "vita tsara"]
INCORRECT_HINTS = ["diso", "tsy marina", "tsy mety", "mbola tsy", "andramo indray"]


def letter_id(i: int) -> str:
    return string.ascii_lowercase[i] if i < 26 else str(i)


def detect_correctness(response_text: str) -> Any:
    text = response_text.lower()
    if any(h in text for h in INCORRECT_HINTS):
        return False
    if any(h in text for h in CORRECT_HINTS):
        return True
    return None


def make_memory_summary(subject: str, topic: str, correct: Any) -> str:
    if correct is True:
        return f"Mpianatra nahavita tsara ny {topic} ({subject})."
    if correct is False:
        return f"Mpianatra mbola sarotra amin'ny {topic} ({subject})."
    return f"Mpianatra mianatra ny {topic} ({subject})."


def convert_assistant_payload(
    old_payload: dict,
    subject: str,
    topic: str,
    turn_index: int,
) -> dict:
    old_action = old_payload.get("action", "none")
    response_text = old_payload.get("reponse", "").strip()
    old_choices = old_payload.get("choix", []) or []

    correct = detect_correctness(response_text)
    is_progress_turn = old_action == "add_user_progression"

    if is_progress_turn:
        action = "add_cursus_content"
        status = "debuter" if turn_index <= 2 else ("a_renforcer" if correct is False else "en_progression")
        if correct is True and turn_index >= 4:
            status = "maitrise"
        choices: Any = {
            "categorie": subject,
            "cursus_categorie": topic,
            "status": status,
        }
    else:
        action = "reponse_chat"
        choices = [
            {"id": letter_id(i), "label": c, "message": c}
            for i, c in enumerate(old_choices)
        ]

    progress = {
        "save": is_progress_turn,
        "skill_id": re.sub(r"[^a-z0-9_]+", "_", topic.lower()).strip("_"),
        "skill_label": topic,
        "evidence": response_text[:80],
        "correct": correct,
        "score": 1 if correct is True else (0 if correct is False else 0),
        "max_score": 1 if is_progress_turn else 0,
        "understanding": 70 if correct is True else (40 if correct is False else 0),
        "xp": 10 if correct is True else (3 if is_progress_turn else 0),
        "lesson_completed": False,
    }

    return {
        "response": response_text,
        "action": action,
        "choices": choices,
        "progress": progress,
        "memory_summary": make_memory_summary(subject, topic, correct),
    }


def convert_record(record: dict) -> dict:
    subject = record.get("subject", "")
    topic = record.get("topic", "")
    new_messages = []
    assistant_turn_index = 0

    for msg in record["messages"]:
        if msg["role"] == "system":
            new_messages.append({"role": "system", "content": NEW_SYSTEM_PROMPT})
        elif msg["role"] == "user":
            new_messages.append(msg)
        elif msg["role"] == "assistant":
            assistant_turn_index += 1
            try:
                old_payload = json.loads(msg["content"])
            except json.JSONDecodeError:
                # Contenu déjà en texte libre (ne devrait pas arriver dans ce corpus) -> on saute
                new_messages.append(msg)
                continue
            new_payload = convert_assistant_payload(
                old_payload, subject, topic, assistant_turn_index
            )
            new_messages.append({
                "role": "assistant",
                "content": json.dumps(new_payload, ensure_ascii=False),
            })
        else:
            new_messages.append(msg)

    new_record = dict(record)
    new_record["messages"] = new_messages
    return new_record


def main(in_path: str, out_path: str) -> None:
    n = 0
    with open(in_path, encoding="utf-8") as fin, open(out_path, "w", encoding="utf-8") as fout:
        for line in fin:
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            new_record = convert_record(record)
            fout.write(json.dumps(new_record, ensure_ascii=False) + "\n")
            n += 1
    print(f"{in_path} -> {out_path} : {n} conversations converties")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python convert_schema.py <input.jsonl> <output.jsonl>")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])