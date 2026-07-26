import os
import urllib.parse
import urllib.request
import urllib.error
from pathlib import Path
import time
import random

# ── Répertoire cible ──────────────────────────────────────────────────────────
BASE_DIR = Path(__file__).resolve().parent
IMAGES_DIR = os.path.join(BASE_DIR, "images")

# ── Configuration ─────────────────────────────────────────────────────────────
MAX_RETRIES = 5          # Nombre de tentatives par image
BASE_DELAY = 8           # Délai de base entre chaque image (secondes)
RETRY_DELAY = 15         # Délai après un 429 avant de réessayer

EDUCATIONAL_THEMES = {
    "mathematiques/fractions": [
        "pie chart fraction puzzles slice of pizza 2D vector flat child illustration white background",
        "cut birthday cake showing fractions simple educational illustration for children white background",
        "colorful fraction visual representations with geometric blocks flat design white background",
        "colorful apples cut in halves and quarters vibrant vector design for school white background"
    ],
    "mathematiques/geometrie": [
        "colorful geometric figures shapes triangle circle square cylinder 3D flat icon illustration white background",
        "kids ruler compass and protractor on blue background cute cartoon school vector",
        "building blocks with basic 3D shapes simple child friendly educational art white background",
        "colorful math gears and shapes floating educational background style white background"
    ],
    "mathematiques/operations": [
        "plus minus multiplication division arithmetic signs cute characters 2D vector white background",
        "colorful abacus wooden counting tool for children mathematics icon vector white background",
        "funny calculator character smiling with numbers floating around children art white background",
        "apples and bananas being counted with simple math addition signs white background"
    ],
    "sciences/volcans": [
        "active volcano erupting lava and lava flows fun educational child illustration white background",
        "cross section cut of earth volcano magma chamber geography textbook graphic white background",
        "dormant green volcano island with ocean and sun children cartoon landscape white background",
        "volcanic rock formation and vapor smoke cloud easy educational flat icon white background"
    ],
    "sciences/systeme_solaire": [
        "solar system planets orbiting around glowing sun colorful child educational art white background",
        "planet earth globe glowing in space with stars cartoon illustration white background",
        "mars Jupiter Saturn colorful 3D planet icons set on dark background",
        "cute astronaut floating near moon and spaceship kids illustration white background"
    ],
    "sciences/plantes": [
        "plant photosynthesis process diagram simple cute trees and water drops solar light white background",
        "seed germination sprouting growing root and leaves in soil step by step educational art white background",
        "colorful flowers and roots underground simple biology textbook cartoon illustration white background",
        "watering can pouring water onto small growing tree seedling environmental art white background"
    ],
    "sciences/corps_humain": [
        "human skeleton biology illustration friendly design for school textbook white background",
        "human lungs and heart colorful simple organ chart illustration for kids white background",
        "brain character glowing with ideas and imagination educational vector icon white background",
        "five senses eyes ears nose mouth hand cute icons for primary school white background"
    ],
    "sciences/laboratoire": [
        "chemistry test tubes beakers flasks with colorful glowing liquid science cartoon white background",
        "microscope tool with glass slides on lab desk cute biology cartoon art white background",
        "science goggles and atom molecule model structure icon flat vector white background",
        "scientist magnifying glass revealing tiny safe cute cells children art white background"
    ],
    "geographie/cartes": [
        "world map globe icon colorful cartoon style with ocean and continents white background",
        "map of Madagascar island shape green surrounded by turquoise ocean simple cartoon vector white background",
        "compass navigation icon and treasure map paper adventure primary school vector white background",
        "mountains rivers oceans geography terrain representation simple 2D flat design white background"
    ],
    "geographie/climat": [
        "sun rain clouds wind thunderstorm seasons weather symbols set flat icon art white background",
        "rain water cycle evaporation condensation precipitation diagram educational style white background",
        "sunny summer beach vs snowy winter mountain split landscape kids art white background",
        "thermometer measuring hot and cold temperatures cute weather vector white background"
    ],
    "histoire/pyramides": [
        "ancient egyptian pyramids in sandy desert with camels history children illustration white background",
        "ancient hieroglyphs symbols on stone wall fun educational textbook graphic white background",
        "sphinx and nile river with palm trees ancient Egypt educational cartoon art white background",
        "archaeologist digging for fossils and dinosaur bones in sand cartoon vector white background"
    ],
    "histoire/dinosaures": [
        "friendly T-Rex dinosaur and diplodocus in prehistoric jungle cartoon illustration white background",
        "fossil imprint of prehistoric fish and fern leaves on rocks geology educational art white background",
        "flying pterodactyl over active prehistoric volcanoes children book illustration white background",
        "dinosaur eggs hatching in prehistoric warm forest colorful illustration white background"
    ],
    "informatique/robotique": [
        "cute friendly AI robot waving hand educational tech illustration for children white background",
        "computer motherboard chip circuits colorful glowing lines flat minimalist vector white background",
        "kid friendly programming coding blocks puzzles interlocking on laptop screen white background",
        "smart devices phone tablet laptop icons connected together simple colorful vector white background"
    ],
    "informatique/cybersecurite": [
        "glowing digital privacy lock and keys on shield cute computer security vector white background",
        "secure strong password star rating checkmark protection badge icon white background",
        "safe surfing online internet worldwide globe connected by shining data lines white background",
        "parent and child happily looking at a safe tablet monitor digital literacy vector white background"
    ],
    "litterature/livres": [
        "stack of magical colorful books opening with stars and imagination flying out white background",
        "open book with glowing fairy tale castle popping out of pages children illustration white background",
        "abc alphabet letter wooden blocks colorful cartoon design white background",
        "quill pen ink pot and old paper scroll writing and literature vector icon white background"
    ],
    "musique/instruments": [
        "classic acoustic guitar and grand piano keyboards colorful cartoon music style white background",
        "floating musical notes treble clef colorful harmony elements on white background",
        "african traditional djembe drum and bamboo flute cultural music educational vector white background",
        "trumpet saxophone violin colorful instruments collection icon set white background"
    ],
    "sante/hygiene": [
        "washing hands with soap bubble foam clean hygiene routine child care cartoon white background",
        "brushing teeth with toothpaste tooth brush cute tooth character smiling white background",
        "healthy fruits and vegetables apple banana broccoli carrots colorful vibrant icon white background",
        "drinking clean mineral glass of water healthy life practices illustration white background"
    ],
    "sante/nutrition": [
        "healthy eating food pyramid chart illustration vegetables grains proteins primary school art white background",
        "plate full of balanced meals rice vegetables fish and fruits colorful cartoon vector white background",
        "glass of milk and cheese calcium dairy healthy nutrition icons white background",
        "fresh tropical fruits orange mango banana watermelon coconut flat design set white background"
    ],
    "education/tableau_noir": [
        "teacher at blackboard with chalk drawings explaining lesson to students cartoon white background",
        "green chalkboard with abc letters and math equations written in chalk white background",
        "classroom whiteboard with colorful markers and educational diagrams white background",
        "student raising hand at desk in front of blackboard cute cartoon white background"
    ],
    "education/diplomes": [
        "graduation cap and diploma scroll with gold ribbon celebration illustration white background",
        "trophy cup and gold medal achievement award cartoon vector for kids white background",
        "gold star sticker and thumbs up reward system illustration for children white background",
        "certificate of achievement template cute design for primary school white background"
    ],
    "education/devoirs": [
        "child writing homework at desk with pencil and notebook cartoon illustration white background",
        "stack of homework papers with checkmarks and gold stars white background",
        "homework assignment sheet with math problems and pencil cartoon white background",
        "student studying with open textbook and lamp at night cute illustration white background"
    ],
    "animaux/animaux_ferme": [
        "cute cartoon farm animals cow chicken pig sheep together in green field white background",
        "happy rooster and hen with baby chicks in barnyard cartoon white background",
        "friendly horse and donkey standing in farm with red barn background white background",
        "cute baby lamb and goat playing in green meadow cartoon illustration white background"
    ],
    "animaux/animaux_sauvages": [
        "lion elephant giraffe zebra safari animals group cartoon illustration white background",
        "colorful tropical parrot toucan flamingo birds collection cartoon white background",
        "ocean underwater sea animals whale dolphin turtle fish cartoon illustration white background",
        "panda bear koala and red fox cute forest animals cartoon white background"
    ],
    "sport/activites_sportives": [
        "children playing soccer football on green field cartoon illustration white background",
        "kids swimming in pool with goggles and swim caps cartoon white background",
        "children running race on athletics track sports day cartoon white background",
        "basketball hoop and ball with kids playing cartoon illustration white background"
    ],
    "environnement/recyclage": [
        "recycling bins green blue yellow sorting trash waste cartoon illustration white background",
        "planet earth hugged by children planting trees environmental cartoon white background",
        "solar panel and wind turbine renewable clean energy cartoon illustration white background",
        "ocean cleanup and beach cleaning volunteers cartoon illustration white background"
    ],
    "environnement/nature": [
        "beautiful forest trees and wildlife deer rabbit squirrel cartoon landscape white background",
        "rainbow over green mountains and river valley cartoon nature scene white background",
        "coral reef underwater with colorful tropical fish cartoon illustration white background",
        "waterfall in tropical jungle with butterflies and flowers cartoon white background"
    ],
}


def generate_image(folder_path, index, prompt):
    """
    Génère une image via Pollinations.ai avec retry et backoff.
    """
    file_path = os.path.join(folder_path, f"{index}.png")

    if os.path.exists(file_path):
        size = os.path.getsize(file_path)
        if size > 1000:  # > 1KB = probablement valide
            print(f"  ✅ Existe déjà : {os.path.relpath(file_path, IMAGES_DIR)}")
            return True
        else:
            os.remove(file_path)  # Fichier corrompu / vide

    style = (
        "2D minimalist educational book illustration for primary school children, "
        "clean vivid flat vector style, perfectly centered, digital art, "
        "high resolution, no text, no letters, bright clean lighting"
    )
    full_prompt = f"{prompt}, {style}"

    encoded_prompt = urllib.parse.quote_plus(full_prompt)
    seed = random.randint(100000, 999999)

    for attempt in range(1, MAX_RETRIES + 1):
        url = f"https://image.pollinations.ai/prompt/{encoded_prompt}?width=800&height=600&seed={seed + attempt}&nologo=1"

        try:
            req = urllib.request.Request(
                url,
                headers={'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64)'}
            )
            with urllib.request.urlopen(req, timeout=60) as response:
                data = response.read()

            if len(data) < 1000:
                print(f"  ⚠️  Tentative {attempt}/{MAX_RETRIES} — image trop petite, retry...")
                time.sleep(RETRY_DELAY)
                continue

            with open(file_path, "wb") as f_out:
                f_out.write(data)

            print(f"  🎉 OK : {os.path.relpath(file_path, IMAGES_DIR)} ({len(data) // 1024} KB)")
            return True

        except urllib.error.HTTPError as e:
            if e.code == 429:
                wait = RETRY_DELAY * attempt
                print(f"  ⏳ 429 Rate-limit — tentative {attempt}/{MAX_RETRIES}, attente {wait}s...")
                time.sleep(wait)
            else:
                print(f"  ❌ HTTP {e.code} — tentative {attempt}/{MAX_RETRIES}")
                time.sleep(RETRY_DELAY)

        except Exception as e:
            print(f"  ❌ Erreur — tentative {attempt}/{MAX_RETRIES} : {str(e)}")
            time.sleep(RETRY_DELAY)

    print(f"  💀 ÉCHEC DÉFINITIF : {os.path.relpath(file_path, IMAGES_DIR)}")
    return False


def main():
    print("=" * 65)
    print("🚀 Génération séquentielle d'images éducatives")
    print(f"   Délai entre images : {BASE_DELAY}s")
    print(f"   Retry si 429       : {MAX_RETRIES} tentatives, {RETRY_DELAY}s backoff")
    print("=" * 65)

    os.makedirs(IMAGES_DIR, exist_ok=True)

    # Compteurs
    total = 0
    success = 0
    failed = 0

    for theme, prompts in EDUCATIONAL_THEMES.items():
        theme_folder = os.path.join(IMAGES_DIR, theme)
        os.makedirs(theme_folder, exist_ok=True)

        print(f"\n📂 {theme} ({len(prompts)} images)")
        print("-" * 50)

        for i, prompt in enumerate(prompts, start=1):
            total += 1
            ok = generate_image(theme_folder, i, prompt)

            if ok:
                success += 1
            else:
                failed += 1

            # Délai entre chaque image pour éviter le 429
            if i < len(prompts):
                print(f"  ⏱️  Pause {BASE_DELAY}s...")
                time.sleep(BASE_DELAY)

        # Pause supplémentaire entre les thèmes
        print(f"  ⏱️  Pause inter-thème {BASE_DELAY + 2}s...")
        time.sleep(BASE_DELAY + 2)

    print("\n" + "=" * 65)
    print(f"✨ Terminé !")
    print(f"   Total   : {total}")
    print(f"   Succès  : {success}")
    print(f"   Échecs  : {failed}")
    print("=" * 65)

    if failed > 0:
        print(f"\n💡 Relance le script pour récupérer les {failed} images manquantes.")
        print("   Les images déjà téléchargées seront ignorées automatiquement.")


if __name__ == "__main__":
    main()