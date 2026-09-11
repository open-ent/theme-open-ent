# theme-open-ent

The default Open ENT NG theme

- Licence : [AGPL v3](http://www.gnu.org/licenses/agpl.txt) - Copyright Conseil Régional Nord Pas de Calais - Picardie

- Développeur(s) : Open Digital Education

- Financeur(s) : Région Nord Pas de Calais-Picardie

- Description : Ce thème est le thème de l'OPEN ENT NG. Basé sur des principes de design simples, répandus et inspirés du matérial design. Il est facilement adaptable à chaque collectivités par la personnalisation du logo et les modifications des codes couleurs : déclinaison orange, rouge, violet, vert, jaune, bleu...

- Emojis designed by OpenMoji – the open-source emoji and icon project. License: [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/#)

---

## Rôle dans l'écosystème

Ce dépôt fournit le **thème serveur legacy** consommé par le framework AngularJS
d'entcore (modules non migrés en React) : feuilles de style compilées (tokens
`--ode-*`), logos, `portal.html`, `theme-conf.js`. Il coexiste avec les bootstraps
React `--openent-*` (`@openent/bootstrap`, `openent-frontend-framework`).

Pour la vue d'ensemble du mécanisme d'habillage (skin / theme / product,
namespaces CSS, publication en artefact et installation à chaud), voir
[`README-THEME.md`](../../README-THEME.md) à la racine de `open-ent-mods`
(section 3a et 5).

## Structure du dépôt

```
scss/           source SCSS commun à tous les déploiements
skins/          variantes de rendu : default, dyslexic
overrides/      un dossier par déploiement (cd16, eclat-bfc, openent1d, openent3,
                paris, reunion, guyane, moncollege… + default) : logo, couleurs,
                i18n propres à ce déploiement
template/       fragments HTML fusionnés dans le build (assistant, auth,
                directory, portal)
assets/         fonts, images, js, i18n globaux copiés tels quels dans dist/
docs/           prévisualisation locale (sert de cible à `dev:serve`)
build.sh        toutes les commandes de build/packaging (voir plus bas)
package-theme.sh  empaquette un dist/ déjà construit en artefact déployable
docker-compose.yml  environnement Node conteneurisé utilisé par build.sh
```

## Développement

Prérequis : `entcore-css-lib` doit être cloné en frère de ce dépôt
(`../entcore-css-lib`) et positionné sur la même branche.

```bash
./build.sh initDev   # installe les dépendances (lien local vers entcore-css-lib)
./build.sh build     # compile le CSS de tous les skins dans build-css/
./build.sh watch     # rebuild + serveur local sur docs/ (travail en cours)
./build.sh lint       # stylelint sur scss/**/*.scss
./build.sh lint-fix
```

Pour tester un skin dans un springboard local sans passer par un artefact :

```bash
./build.sh buildLocal   # build + copie dans ../recette/assets/themes/theme-open-ent
```

Détails complémentaires : [`CONTRIBUTING.md`](CONTRIBUTING.md).

### Ajouter ou modifier un override

Chaque déploiement a son dossier dans `overrides/<nom>/` (logo, `css/`
surchargeant les variables SCSS, i18n propre). Le build se lance alors avec
`-o=<nom>` :

```bash
./build.sh build -o=cd16
```

## Empaqueter un artefact de déploiement

`package-theme.sh` transforme un `dist/` déjà construit en `theme-<skin>-<version>.tar.gz`
(+ `.sha256`), le format publié en GitHub Release et installé par l'ENT
(cf. `README-THEME.md` §5) :

```bash
./build.sh build -o=cd16
./package-theme.sh --skin=cd16 --version=3.4.10-42
```

## Commandes `build.sh`

| Commande       | Effet |
|----------------|-------|
| `clean`        | supprime `node_modules`, `dist`, `build`, `build-css`, lockfiles, `package.json` généré |
| `init`         | génère `package.json` depuis le template, installe les dépendances (version publiée de `entcore-css-lib`) |
| `initDev`      | idem, mais lie `entcore-css-lib` en local (`link:`) |
| `build`        | compile le CSS de tous les skins dans `build-css/`, fusionne assets/template/i18n de l'override |
| `buildLocal`   | `build` + copie dans `../recette/assets/themes/theme-open-ent` |
| `install`      | `build` + `archive` + installation Maven locale |
| `watch`        | rebuild + serveur local (travail en cours) |
| `lint` / `lint-fix` | stylelint |
| `archive`      | empaquette `dist/` en `.tar.gz` (variante interne, cf. `package-theme.sh` pour l'artefact de déploiement) |
| `publishNPM`   | publie le paquet npm (tag = branche courante) |
| `publishNexus` | publie l'archive Maven sur Nexus (snapshots/releases selon `MVN_MOD_VERSION`) |

Chaque commande accepte `-o=<override>` (défaut `default`) ; le nom du module
publié devient alors `ode-csslib-openent-<override>`.

> ⚠️ `README.md` est régénéré depuis [`README.md.template`](README.md.template)
> par `build.sh init`/`initDev` (et supprimé si l'override n'existe pas dans
> `overrides/`). Toute modification de ce fichier doit être répercutée dans le
> template pour ne pas être perdue au prochain `init`.
