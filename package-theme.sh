#!/usr/bin/env bash
# =============================================================================
# Empaquette le dist/ d'un thème déjà construit en artefact distribuable.
#
# Produit, dans --out-dir :
#   theme-<skin>-<version>.tar.gz
#   theme-<skin>-<version>.tar.gz.sha256
#
# C'est l'artefact publié en GitHub Release et téléchargé par l'ENT (init
# container sync-themes au démarrage, ThemeInstaller pour l'installation à
# chaud). Un seul script pour la CI et pour le local : les deux doivent produire
# le même tar, sinon la somme de contrôle publiée ne veut plus rien dire.
#
# Contenu de l'archive :
#   theme/       -> installé tel quel dans assets/themes/<skin>/
#   i18n/        -> fusionné dans assets/i18n/   (surcharges GLOBALES de libellés,
#                   absentes de dist/ : build.sh ne les y met jamais, elles vivent
#                   dans assets/i18n/ du dépôt de thème et valent pour tous les skins)
#   theme.json   -> manifeste lu par l'installateur et par le dashboard
#
# Usage :
#   ./package-theme.sh --skin=cd16 --version=3.4.10-42 [--dist=dist] [--out-dir=artifacts]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SKIN=""
VERSION=""
DIST_DIR="$SCRIPT_DIR/dist"
OUT_DIR="$SCRIPT_DIR/artifacts"

for arg in "$@"; do
    case "$arg" in
        --skin=*)    SKIN="${arg#*=}" ;;
        --version=*) VERSION="${arg#*=}" ;;
        --dist=*)    DIST_DIR="${arg#*=}" ;;
        --out-dir=*) OUT_DIR="${arg#*=}" ;;
        *) echo "Option inconnue : $arg" >&2; exit 1 ;;
    esac
done

[[ -n "$SKIN"    ]] || { echo "ERREUR : --skin manquant" >&2; exit 1; }
[[ -n "$VERSION" ]] || { echo "ERREUR : --version manquant" >&2; exit 1; }
[[ -d "$DIST_DIR" ]] || { echo "ERREUR : dist introuvable : $DIST_DIR (lancer build.sh avant)" >&2; exit 1; }

# Le skin devient un nom de répertoire côté PVC et un segment d'URL : le contraindre
# ici évite qu'un identifiant fabriqué ailleurs ne remonte l'arborescence.
[[ "$SKIN" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || { echo "ERREUR : skin invalide : $SKIN" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "→ Assemblage de l'artefact $SKIN $VERSION"

mkdir -p "$STAGE/theme"
cp -a "$DIST_DIR/." "$STAGE/theme/"

# Sources de maquettage : elles pèsent jusqu'à 4,5 Mo pièce (logo-text.xcf) et ne
# sont jamais servies en HTTP. Elles n'ont rien à faire dans un artefact tiré par
# chaque cluster à chaque publication.
find "$STAGE/theme" \( -name '*.xcf' -o -name '*.psd' -o -name '*.ai' \) -print -delete

# Surcharges i18n globales — cf. en-tête. Identiques pour tous les skins (elles
# valent pour la plateforme, pas pour un déploiement), donc jointes à chaque
# artefact : 16 Ko, et l'installation reste idempotente quel que soit l'ordre.
# L'image assets les porte aussi ; sync-themes passant APRÈS copy-assets, c'est
# la version de l'artefact qui fait foi, et un déploiement sans thème épinglé
# garde malgré tout des libellés.
if [[ -d "$SCRIPT_DIR/assets/i18n" ]]; then
    mkdir -p "$STAGE/i18n"
    cp -a "$SCRIPT_DIR/assets/i18n/." "$STAGE/i18n/"
fi

# Métadonnées de conf front : le skin doit figurer dans `theme-conf.js` pour que les
# applications React posent data-theme/data-product — absent de cette liste, le front
# écrit littéralement data-theme="undefined" et perd son thème (constaté sur occitanie).
# L'artefact les transporte donc, et l'installateur complète `theme-conf.js` tout seul.
# `theme-meta.json` de l'override fait foi ; à défaut, le gabarit 2d, le plus courant.
BOOTSTRAP_VERSION="ode-bootstrap-neo"
HELP_PATH="/help-2d"
META_FILE="$SCRIPT_DIR/overrides/$SKIN/theme-meta.json"
if [[ -f "$META_FILE" ]]; then
    value_of() { sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$META_FILE" | head -1; }
    [[ -n "$(value_of bootstrapVersion)" ]] && BOOTSTRAP_VERSION="$(value_of bootstrapVersion)"
    [[ -n "$(value_of help)" ]] && HELP_PATH="$(value_of help)"
fi

SKINS_JSON="[]"
if [[ -d "$DIST_DIR/skins" ]]; then
    SKINS_JSON="$(find "$DIST_DIR/skins" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
        | sort | sed 's/.*/"&"/' | paste -sd, - | sed 's/^/[/; s/$/]/')"
fi

THEME_SHA="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"

# Pas de date de construction dans le manifeste : elle suffirait à donner deux
# sommes de contrôle différentes pour des sources identiques, et on perdrait la
# seule chose qui permette de vérifier qu'un artefact publié correspond bien à un
# commit. La date de publication vit dans la Release GitHub, et `themeOpenEntSha`
# identifie la source à l'exactitude du commit.
cat > "$STAGE/theme.json" <<JSON
{
  "skin": "$SKIN",
  "version": "$VERSION",
  "themeOpenEntSha": "$THEME_SHA",
  "bootstrapVersion": "$BOOTSTRAP_VERSION",
  "help": "$HELP_PATH",
  "skins": $SKINS_JSON
}
JSON

mkdir -p "$OUT_DIR"
ARCHIVE="$OUT_DIR/theme-$SKIN-$VERSION.tar.gz"

# --sort=name + mtime/owner figés : deux empaquetages du même dist produisent le
# même tar, donc la même somme de contrôle — d'où l'absence de date dans theme.json.
# Sans cela, impossible de vérifier qu'un artefact republié est bien identique.
tar --sort=name \
    --mtime='UTC 2020-01-01' \
    --owner=0 --group=0 --numeric-owner \
    -czf "$ARCHIVE" \
    -C "$STAGE" .

( cd "$OUT_DIR" && sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256" )

echo "✔  $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
echo "✔  $(cat "$ARCHIVE.sha256")"
