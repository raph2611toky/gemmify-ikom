# helpers/db/tutorials_repository.py
import sqlite3
import os
from pathlib import Path
from contextlib import contextmanager

BASE_DIR = Path(__file__).resolve().parent.parent.parent
DB_DIR   = os.path.join(BASE_DIR, "database")
DB_PATH  = os.path.join(DB_DIR, "gemmify_ikom.db")

os.makedirs(DB_DIR, exist_ok=True)


@contextmanager
def get_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db():
    with get_connection() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS tutorials (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sujet TEXT NOT NULL,
                contexte TEXT,
                duree_max INTEGER,
                video_path TEXT NOT NULL,
                script TEXT,
                sexe TEXT,
                email TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        """)


def insert_tutorial(
    sujet: str,
    contexte: str,
    duree_max: int,
    video_path: str,
    script: str,
    sexe: str,
    email: str | None = None
) -> int:
    with get_connection() as conn:
        cur = conn.execute(
            """
            INSERT INTO tutorials (sujet, contexte, duree_max, video_path, script, sexe, email)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (sujet, contexte, duree_max, video_path, script, sexe, email)
        )
        return cur.lastrowid


def get_tutorials_by_contexte(contexte: str) -> list[dict]:
    contexte_norm = (contexte or "").strip().lower()
    with get_connection() as conn:
        rows = conn.execute(
            """
            SELECT * FROM tutorials
            WHERE LOWER(TRIM(contexte)) = ?
            ORDER BY created_at DESC
            """,
            (contexte_norm,)
        ).fetchall()
        return [dict(row) for row in rows]


def get_tutorial_by_id(video_id: int) -> dict | None:
    with get_connection() as conn:
        row = conn.execute(
            "SELECT * FROM tutorials WHERE id = ?", (video_id,)
        ).fetchone()
        return dict(row) if row else None