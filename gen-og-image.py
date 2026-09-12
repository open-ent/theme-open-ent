#!/usr/bin/env python3
"""
Génère l'image de partage (Open Graph) d'un thème : overrides/<skin>/img/illustrations/og-image.png

Pourquoi : c'est la vignette qu'affichent Discord, Slack, WhatsApp, LinkedIn… quand on colle un
lien vers l'ENT. Sans elle, l'aperçu retombe sur un logo carré transparent, illisible sur le fond
sombre de ces applications — et, avant le correctif de portal-mui, sur le logo d'une AUTRE instance.

Format : 1200x630 (le ratio attendu par `twitter:card = summary_large_image`), fond OPAQUE — une
transparence est composée sur le thème du lecteur, donc imprévisible.

Choix de la source : parmi les logos du thème, le premier qui soit à la fois large et LISIBLE sur
blanc. Beaucoup de thèmes ont deux logos de même nom à des chemins différents, l'un coloré et
l'autre blanc (prévu pour le bandeau coloré du portail) : composer le blanc sur blanc donne une
vignette vide, ce qui ne se voit qu'à l'usage. On mesure donc la luminance des pixels opaques, et
si tous les candidats sont clairs on bascule le fond sur la couleur de marque du thème.

Usage : ./gen-og-image.py occitanie [autre-skin…]   (sans argument : tous les thèmes)
"""
import hashlib, json, os, sys
from PIL import Image

W, H, MARGIN = 1200, 630, 96
# Du plus lisible en large au moins bon. Le même nom apparaît à deux chemins : ils ne portent pas
# la même image (cf. logo blanc / logo coloré).
SOURCES = ("img/logo-text.png", "img/logo1536x1024.png",
           "img/illustrations/logo-dashboard.png", "img/logo.png",
           "img/illustrations/logo.png")
LIGHT = 200          # au-delà, le logo se confond avec un fond blanc
DARK_FALLBACK = "#15223d"
GENERIC = "openent3"  # thème dont les autres héritent leurs fichiers non surchargés
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "overrides")


def digest(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def inherited(skin, name, path):
    """Vrai si le thème n'a pas surchargé ce fichier : c'est celui d'openent3 recopié tel quel.

    Sans ce filtre, un thème qui garde le mot-symbole générique — c'est le cas d'eclat-bfc, dont
    logo-text.png EST celui d'Open ENT — se verrait attribuer la vignette d'Open ENT alors qu'il
    porte sa propre marque ailleurs (img/logo.png)."""
    if skin == GENERIC:
        return False
    generic = os.path.join(ROOT, GENERIC, name)
    return os.path.isfile(generic) and digest(generic) == digest(path)


def luminance(image):
    """Luminance moyenne des pixels opaques — 255 = logo blanc, invisible sur blanc."""
    pixels = image.load()
    total = count = 0
    for y in range(0, image.height, 3):
        for x in range(0, image.width, 3):
            r, g, b, a = pixels[x, y]
            if a > 128:
                total += 0.2126 * r + 0.7152 * g + 0.0722 * b
                count += 1
    return total / count if count else 255


def brand_color(base):
    """Couleur de marque du thème, celle qu'écrit l'éditeur de thème. À défaut, un bleu nuit."""
    try:
        with open(os.path.join(base, "dashboard.json"), encoding="utf-8") as f:
            return json.load(f).get("primaryColor") or DARK_FALLBACK
    except (OSError, ValueError):
        return DARK_FALLBACK


def generate(skin):
    base = os.path.join(ROOT, skin)
    candidates = []
    for name in SOURCES:
        path = os.path.join(base, name)
        if not os.path.isfile(path):
            continue
        logo = Image.open(path).convert("RGBA")
        box = logo.getbbox()          # rogne la marge interne du logo, sinon la vignette paraît vide
        if box:
            logo = logo.crop(box)
        candidates.append((name, logo, luminance(logo), inherited(skin, name, path)))

    if not candidates:
        print(f"{skin:<14} ignoré — aucun logo exploitable")
        return False

    readable = [c for c in candidates if c[2] < LIGHT]
    # La marque du thème d'abord ; un fichier hérité d'openent3 ne sert que faute de mieux.
    own = [c for c in readable if not c[3]]
    name, logo, _, from_generic = (own or readable or candidates)[0]
    background = "white" if readable else brand_color(base)

    scale = min((W - 2 * MARGIN) / logo.width, (H - 2 * MARGIN) / logo.height)
    logo = logo.resize((max(1, round(logo.width * scale)),
                        max(1, round(logo.height * scale))), Image.LANCZOS)

    canvas = Image.new("RGBA", (W, H), background)
    canvas.alpha_composite(logo, ((W - logo.width) // 2, (H - logo.height) // 2))

    out = os.path.join(base, "img/illustrations/og-image.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.convert("RGB").save(out, "PNG", optimize=True)
    print(f"{skin:<14} {name:<38} fond {background:<9} -> og-image.png "
          f"({os.path.getsize(out) // 1024} Ko)"
          + ("  [hérité d'openent3, marque propre absente]" if from_generic else ""))
    return True


if __name__ == "__main__":
    skins = sys.argv[1:] or sorted(os.listdir(ROOT))
    # Pas de any(...) : il court-circuite au premier succès et n'en traiterait qu'un seul.
    if not [s for s in skins if generate(s)]:
        sys.exit(1)
