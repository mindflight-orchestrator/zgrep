# zgr

[English](README.md) | [Français](README.fr.md)

Recherche de texte rapide et compatible avec grep, écrite en Zig 0.16 pour
x86_64 GNU/Linux.

`zgr` combine une recherche optimisée de chaînes littérales et d'expressions
régulières avec une sortie conforme aux conventions GNU. Il est conçu pour les
fichiers volumineux et les recherches récursives dans les arbres de sources,
tout en conservant une sortie ordonnée et une utilisation mémoire bornée.

> [!IMPORTANT]
> Il s'agit d'une implémentation récente, pas encore d'un remplacement direct
> et complet pour toutes les options de GNU grep. La compatibilité et les
> performances sont continuellement vérifiées face à GNU grep et ripgrep.

## Vue d'ensemble

| Élément | Valeur |
|---|---|
| Exécutable | `zgr` |
| Syntaxe par défaut | Expressions régulières basiques (BRE) |
| Autres modes | ERE avec `-E`, chaînes fixes avec `-F`, PCRE avec `-P` |
| Plateforme | x86_64 GNU/Linux |
| Chaîne d'outils | Zig 0.16.0 |
| Dépendances natives | glibc et PCRE2 8 bits |
| État du projet | Implémentation récente |

L'exécutable s'appelle `zgr` pour éviter une collision avec la commande système
traditionnelle `zgrep`, utilisée pour les fichiers compressés.

## Points forts

- Recherche littérale rapide grâce au SIMD et à un saut inspiré de
  Boyer-Moore-Horspool.
- JIT PCRE2 pour les charges BRE, ERE et PCRE compatibles, avec des replis
  GNU/POSIX lorsque la sémantique diffère.
- Traitement parallèle ordonné pour les fichiers volumineux et les arbres de
  répertoires récursifs.
- Mémoire bornée pour l'entrée en flux, les sorties denses et les charges
  récursives.
- Gestion des données binaires, du contexte, des couleurs, des filtres et des
  diagnostics conforme aux conventions GNU.
- Tests différentiels, fuzzing et benchmarks vérifiés face à GNU grep et
  ripgrep.

## Démarrage rapide

### Prérequis

- Zig 0.16.0
- x86_64 GNU/Linux
- Fichiers de développement PCRE2 8 bits

### Compilation

```sh
zig build -Doptimize=ReleaseFast
```

L'exécutable de production dépouillé de ses symboles est écrit dans
`zig-out/bin/zgr`. Les compilations de débogage conservent les symboles.

### Installation

```sh
make
sudo make install
```

Cela copie `zgr` dans `/usr/local/bin`. Remplacez la destination avec `PREFIX`,
par exemple `make install PREFIX=$HOME/.local`. Désinstallez avec
`sudo make uninstall`.

### Exemples

```sh
# La syntaxe des expressions régulières basiques est utilisée par défaut.
zig-out/bin/zgr 'needle' large.log

# Utiliser explicitement les expressions régulières étendues.
zig-out/bin/zgr -E -n 'error|warning' src/*.zig

# Rechercher récursivement une chaîne fixe et afficher les numéros de ligne.
zig-out/bin/zgr -F -r -n 'CONFIG_' /path/to/tree

# Compter les correspondances d'une chaîne fixe sans tenir compte de la casse.
zig-out/bin/zgr -F -i -c 'content-length' access.log

# Afficher uniquement les segments correspondants avec lignes et offsets.
zig-out/bin/zgr -E -n -b -o 'request_[0-9]+' access.log
```

Le code de sortie suit les conventions de grep :

- `0` : au moins une ligne a été sélectionnée ;
- `1` : aucune ligne n'a été sélectionnée ;
- `2` : une erreur s'est produite.

## Comportements pris en charge

| Domaine | Prise en charge actuelle |
|---|---|
| Syntaxe des motifs | BRE, ERE, chaînes fixes, PCRE, plusieurs motifs `-e` et fichiers de motifs `-f` |
| Correspondance | Casse, inversion, mots entiers, lignes entières et segments `-o` POSIX gauche-le-plus-tôt/plus-long |
| Sortie | Comptages, numéros de ligne, offsets, segments correspondants, noms de fichiers, groupes de contexte et nombres maximaux |
| Recherche récursive | `-r`, `-R`, sortie ordonnée, `--include`, `--exclude`, `--exclude-from` et `--exclude-dir` |
| Données binaires | Modes GNU `binary`, `text` et `without-match`, ainsi que `-a`, `-I` et `-U` |
| Formats d'enregistrement | Enregistrements délimités par un saut de ligne ou NUL, avec noms de fichiers terminés par NUL indépendamment |
| Sortie du terminal | `--color`/`--colour`, `GREP_COLORS`, `--initial-tab` et `--line-buffered` |
| Entrées | Fichiers ordinaires, entrée standard, FIFO et périphériques explicites ; les périphériques récursifs nécessitent `-D read` |
| Régionalisation | Classes UTF-8, gestion de la casse et limites de mots compatibles GNU via libc |

Exécutez `zig-out/bin/zgr --help` pour obtenir la liste complète des options.

## Conception des performances

Les chemins courants sont choisis selon le motif, le type d'entrée et la sortie
demandée :

- les grands fichiers ordinaires sont mappés en mémoire, tandis que les petits
  utilisent des lectures positionnelles avec tampon ;
- les candidats littéraux utilisent le SIMD et une recherche par sauts ;
- les expressions régulières compatibles utilisent le JIT PCRE2, avec des
  chemins spécialisés ou compatibles GNU lorsque PCRE2 interpréterait la
  sémantique différemment ;
- les charges de comptage et de sortie admissibles s'exécutent en parallèle
  tout en préservant l'ordre GNU ;
- les métadonnées spéculatives et les sorties capturées restent soumises à des
  limites mémoire explicites.

<details>
<summary>Architecture détaillée de la correspondance et des E/S</summary>

### Moteurs de correspondance

- Les motifs BRE et ERE compatibles non littéraux utilisent le JIT PCRE2.
- La validation ou l'exécution par les expressions régulières GNU est conservée
  pour les constructions dont le comportement diffère de PCRE2.
- Les expressions `-o` compatibles mais ambiguës utilisent l'automate déterministe
  PCRE2 afin de préserver les segments POSIX gauche-le-plus-tôt/plus-long.
- Les séquences ERE positives composées de classes ASCII entre crochets, de
  répétitions exactes et de `+` peuvent utiliser un automate non déterministe
  bit-parallèle borné à 64 états sur les enregistrements ASCII avérés.
- Les expressions régulières à littéral requis peu fréquent sautent directement
  entre les enregistrements candidats et classent la densité du préfiltre au
  cours du même parcours.

### Travail parallèle

- Les comptages de littéraux, d'alternances littérales, de séquences de classes
  et PCRE2 utilisent un état mutable propre à chaque thread.
- Les comptages de séquences de classes ASCII avérées utilisent un budget
  calibré de 6 Mio par worker ; le chemin général de comptage des expressions
  régulières utilise 8 Mio par worker.
- La sortie des grands fichiers emploie une découverte parallèle, bornée et
  ordonnée des correspondances lorsque le mode choisi le permet. Elle bascule
  avant la sortie si son plafond de métadonnées risque d'être dépassé.
- Les listes récursives et les sorties de lignes complètes préservent l'ordre de
  parcours. Les arbres d'au moins 512 fichiers ordinaires utilisent un pipeline
  producteur/consommateur borné afin que l'analyse commence pendant le parcours.
- Les recherches récursives rapides, littérales ou à littéral requis, utilisent
  jusqu'à 12 workers ; les expressions régulières coûteuses sans préfiltre
  conservent une limite de 16 workers.

### Mémoire et traitement en flux

- Les workers de sortie récursive formatent dans des tampons temporaires de
  64 Kio et ne conservent que les octets produits, dans un budget partagé de
  16 Mio pour les données utiles.
- La sortie littérale depuis l'entrée standard reste traitée en flux et bornée
  par la longueur du plus grand enregistrement d'entrée.
- Les candidats contenant des octets NUL basculent avant l'émission ordonnée ;
  les résumés UTF-8 invalides se propagent dans l'ordre de parcours.
- Les échecs d'écriture avec tampon ou ligne par ligne préservent l'erreur de
  fichier Zig sous-jacente, notamment `zgr: write error: Broken pipe`.

### Détails orientés GNU

- Le contexte avant, après et symétrique utilise le regroupement, les
  séparateurs et les préfixes de correspondance/contexte de GNU.
- Les enregistrements de données NUL restent terminés par NUL, tandis que les
  groupes de contexte séparés conservent le séparateur de groupe GNU terminé
  par un saut de ligne.
- `--initial-tab` reproduit les largeurs de champs GNU adaptées à la taille pour
  les fichiers ordinaires et la largeur de taille inconnue pour les pipes.
- La coloration ANSI prend en charge les alias GNU et les capacités
  `GREP_COLORS` pour les correspondances, noms de fichiers, offsets,
  séparateurs et contextes.
- Les environnements régionaux UTF-8 utilisent la sémantique libc pour les
  classes Unicode, la casse et les limites de mots. Les entrées ASCII avérées
  utilisent les chemins optimisés ; les entrées non ASCII ou mal formées
  conservent les replis GNU nécessaires.

</details>

## Vérification

### Suite standard

```sh
zig build test
```

Cette commande exécute les tests unitaires Zig et les principaux parcours
différentiels GNU, notamment :

- la matrice générale de comportement de la ligne de commande ;
- 59 cas sémantiques BRE/ERE ;
- 141 cas de régionalisation UTF-8 sur les environnements `C.utf8`,
  `en_US.utf8` et `nl_BE.utf8` disponibles ;
- les flux d'octets de couleur ANSI, les FIFO, la gestion binaire/NUL et le
  comportement en cas de pipe cassé.

La [comparaison avec la suite officielle de GNU grep 3.12](docs/gnu-grep-3.12-compatibility.fr.md)
consigne les résultats de l'exécution du banc fonctionnel GNU inchangé de
128 tests contre les deux moteurs d'expressions régulières.

### Fuzzing déterministe des expressions régulières

```sh
zig build test-fuzz -Doptimize=ReleaseFast
```

Utilisez `ZGREP_FUZZ_SEED` et `ZGREP_FUZZ_ITERATIONS` pour reproduire ou
étendre une exécution.

### Stress des grands fichiers et de la récursion

```sh
zig build test-stress -Doptimize=ReleaseFast
```

La suite de stress génère des corpus de plus de 64 Mio, délimités par des sauts
de ligne ou par NUL. Elle teste face à GNU grep les seuils de sortie parallèle,
les replis pour correspondances denses, les pipelines récursifs de plus de
512 fichiers, l'ordre exact de sortie, les résumés binaires et la gestion de
l'UTF-8 invalide.

<details>
<summary>Scénarios ripgrep réutilisés</summary>

Les scénarios portables de `tests/differential.sh` adaptent les cas de nombre
maximal, de fichiers de motifs dupliqués, de données binaires/NUL, de contexte
et de régression issus de la suite de tests MIT/Unlicense de ripgrep au commit
`3fce3b5bb0236da2df6d99672afb8a719642eca7`.

Le banc de test Rust de ripgrep dépend lui-même d'options propres à rg ; il ne
peut donc pas exécuter sans modification un programme compatible avec grep. La
suite locale conserve les cas comportementaux portables et valide leurs
résultats indépendamment.

</details>

## Benchmarks

Le dépôt contient des benchmarks conditionnés par la justesse pour un grand
fichier structuré et des arbres comprenant de nombreux petits fichiers. Chaque
résultat candidat est comparé à GNU grep avant d'être chronométré.

La dernière comparaison enregistrée est documentée dans
[docs/benchmark-v0.3.fr.md](docs/benchmark-v0.3.fr.md).

### Corpus généré

```sh
bench/generate.sh /tmp/zgrep-bench.txt 3000000
BENCH_BATCHES=5 ZGR=./zig-out/bin/zgr \
  bench/run.sh /tmp/zgrep-bench.txt 20
```

### Arbre de sources existant

```sh
BENCH_PROFILE=ripgrep-linux-default BENCH_BATCHES=5 BENCH_CPUSET=0-15 \
  ZGR=./zig-out/bin/zgr \
  bench/run-tree.sh /path/to/linux PM_RESUME 5
```

Répétez les mesures de performances sur un système par ailleurs inactif avant
de formuler des affirmations entre machines.

<details>
<summary>Profils de benchmark et contrôles de reproductibilité</summary>

### Charges supplémentaires

```sh
# Corpus généré délimité par NUL
bench/generate.sh /tmp/zgrep-bench-nul.dat 3000000 nul
BENCH_BATCHES=5 ZGR=./zig-out/bin/zgr \
  bench/run-null.sh /tmp/zgrep-bench-nul.dat 20

# Charge Sherlock de ripgrep
BENCH_PROFILE=ripgrep-sherlock BENCH_BATCHES=9 BENCH_CPUSET=0-15 \
  ZGR=./zig-out/bin/zgr \
  bench/run.sh /path/to/ripgrep/tests/data/sherlock-nul.txt 50

# Profil Linux en mode texte forcé
BENCH_PROFILE=ripgrep-linux BENCH_BATCHES=5 BENCH_CPUSET=0-15 \
  ZGR=./zig-out/bin/zgr \
  bench/run-tree.sh /path/to/linux PM_RESUME 5

# Échantillons d'arbre à cache froid
BENCH_CACHE=cold BENCH_BATCHES=3 BENCH_CPUSET=0-15 \
  ZGR=./zig-out/bin/zgr \
  bench/run-tree.sh /path/to/ripgrep SearcherBuilder 1
```

### Contrôles

- `BENCH_BATCHES` indique la moyenne, la médiane, le 95e centile, le minimum et
  le maximum de lots chronométrés indépendamment.
- `BENCH_LOCALE` choisit l'environnement régional ; `C` est utilisé par défaut
  et `C.utf8` exerce les chemins dépendant de l'environnement régional.
- `BENCH_CPUSET` fixe les commandes au moyen de `taskset` pour stabiliser les
  exécutions sur processeurs hybrides.
- `BENCH_CACHE=cold` évince le corpus hors de la zone chronométrée et impose une
  répétition par lot.
- La sortie du benchmark est écrite dans des fichiers temporaires ordinaires
  plutôt que dans `/dev/null`, afin d'éviter que des raccourcis de sortie ne
  faussent les résultats.
- Les scripts acceptent l'ancienne variable `ZGREP` comme solution de repli pour
  `ZGR`.

Les profils `ripgrep-sherlock`, `ripgrep-linux` et `ripgrep-linux-default`
adaptent les familles de charges littérales, par mot, avec alternance, à
littéral requis et sans littéral de ripgrep. Le profil Linux par défaut préserve
le comportement normal de chaque outil pour les fichiers binaires ; le profil
en texte forcé utilise des modes texte explicites.

</details>

## Intégration continue et publications

[GitHub Actions](.github/workflows/ci.yml) exécute les tests Debug, ReleaseSafe
et ReleaseFast sur Ubuntu 24.04. Le parcours ReleaseFast exécute également le
fuzzing déterministe, la suite de stress de plus de 64 Mio et un test rapide de
benchmark vérifié dans `C.utf8`.

Les tags annotés `v*` déclenchent le
[workflow de publication](.github/workflows/release.yml). Celui-ci vérifie que
le tag correspond à `src/main.zig` et `build.zig.zon`, relance les contrôles de
publication et publie une archive x86_64 GNU/Linux dépouillée de ses symboles,
accompagnée de sa somme de contrôle SHA-256.

Les archives de publication sont liées dynamiquement à glibc et au runtime
PCRE2 8 bits ; elles ne sont pas présentées comme des binaires Linux statiques
ou universellement portables.

## Licence

[MIT](LICENSE)
