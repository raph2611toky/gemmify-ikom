import os
import sys
from pathlib import Path
from PIL import Image
from rembg import remove, new_session
import time
import io

BASE_DIR = Path(__file__).resolve().parent
IMAGES_DIR = os.path.join(BASE_DIR, "images")


def process_image(file_path: str, session) -> bool:
    try:
        with open(file_path, "rb") as f:
            input_data = f.read()

        if len(input_data) < 1000:
            print(f"  ⚠️  Fichier trop petit, ignoré : {file_path}")
            return False

        # Suppression du background
        output_data = remove(
            input_data,
            session=session,
            alpha_matting=True,
            alpha_matting_foreground_threshold=240,
            alpha_matting_background_threshold=10,
            alpha_matting_erode_size=10
        )

        img = Image.open(io.BytesIO(output_data))
        if img.mode != "RGBA":
            img = img.convert("RGBA")

        img.save(file_path, format="PNG", optimize=True)

        return True

    except Exception as e:
        print(f"  ❌ Erreur sur {file_path} : {str(e)}")
        return False


def main():
    print("=" * 65)
    print("🔄 Suppression des backgrounds — Dataset éducatif")
    print("=" * 65)

    if not os.path.exists(IMAGES_DIR):
        print(f"❌ Dossier introuvable : {IMAGES_DIR}")
        sys.exit(1)

    all_images = []
    for root, dirs, files in os.walk(IMAGES_DIR):
        for f in sorted(files):
            if f.lower().endswith(".png"):
                all_images.append(os.path.join(root, f))

    if not all_images:
        print("❌ Aucune image PNG trouvée.")
        sys.exit(1)

    print(f"📊 {len(all_images)} images trouvées.\n")

    print("⏳ Chargement du modèle IA (u2net)...")
    session = new_session("u2net")
    print("✅ Modèle chargé.\n")

    success = 0
    failed = 0
    start_time = time.time()
    current_folder = ""

    for i, img_path in enumerate(all_images, start=1):

        folder = os.path.relpath(os.path.dirname(img_path), IMAGES_DIR)
        if folder != current_folder:
            current_folder = folder
            print(f"\n📂 {current_folder}")
            print("-" * 50)

        filename = os.path.basename(img_path)
        print(f"  [{i}/{len(all_images)}] {filename} ... ", end="", flush=True)

        ok = process_image(img_path, session)

        if ok:
            success += 1
            size_kb = os.path.getsize(img_path) // 1024
            print(f"✅ ({size_kb} KB)")
        else:
            failed += 1
            print("❌")

    elapsed = time.time() - start_time

    print("\n" + "=" * 65)
    print(f"✨ Terminé en {elapsed:.1f}s")
    print(f"   Total    : {len(all_images)}")
    print(f"   Succès   : {success}")
    print(f"   Échecs   : {failed}")
    print(f"   Vitesse  : {elapsed / len(all_images):.1f}s / image")
    print("=" * 65)


if __name__ == "__main__":
    main()