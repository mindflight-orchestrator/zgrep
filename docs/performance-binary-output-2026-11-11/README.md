# Détection binaire progressive : preuves et reproduction

[Rapport lisible et résultats](../performance-audit.fr.md#optimisation-retenue--détection-binaire-progressive)

La référence est le commit `cbed1de`, qui contient déjà le comptage adaptatif.
Le candidat est le correctif local décrit par `retained-change.patch`. Les
empreintes identifient les sources et les binaires réellement qualifiés et
mesurés. Ces captures ne constituent ni un commit ni une publication.

| Fichier | Contenu |
|---|---|
| `metadata.json`, `baseline-inputs.json`, `candidate-inputs.json` | Versions, compilation, périmètre, empreintes et résultats de validation |
| `retained-change.patch` | Correctif applicatif depuis `cbed1de` ; les outils de mesure sont séparés |
| `final-auto.json`, `final-auto.log` | Programmes complets, locale C, un CPU, 25 tours, options binaires normales pour tous |
| `final-utf8.json`, `final-utf8.log` | Même comparaison pour les sorties littérales en locale C.UTF-8 |
| `final-text.json`, `final-text.log` | Contrôle avec `-a` pour tous, qui contourne la nouvelle détection |
| `final-four-core.json`, `final-four-core.log` | Corpus de 93,8 Mo, quatre CPU, 15 tours ; chemin parallèle conservé |
| `final-medium.json`, `final-medium.log` | Corpus de 18,8 Mo, quatre CPU disponibles, 15 tours ; détection NUL parallèle conservée |
| `medium-confirmation.json`, `confirm-medium.py` | Contrôle prolongé sur 18,8 Mo, 61 tours |
| `final-small.json`, `final-small.log` | Corpus de 7,5 Mo, quatre CPU disponibles, 25 tours ; nouveau chemin séquentiel admissible |
| `final-micro.json`, `final-micro.log` | Treize fonctions internes, corpus résident, 25 tours, un CPU |
| `summary.json` | Médianes, réductions de temps appariées et intervalles à 95 % |
| `compare-output.py`, `final-measurements.py` | Recette des séries exécutées successivement |
| `qualification-fast.log`, `qualification-zgr-binary.log` | Tests principaux et nouveaux contrôles binaires réussis |
| `qualification-safe.log`, `qualification-safe-binary.log` | Tests unitaires et contrôles binaires en ReleaseSafe |
| `baseline-*.log`, `candidate-*-semantics.log` | Reproduction des deux échecs de zpcre2 sur la référence et le candidat |
| `edge-findings.json` | Doublon de diagnostic corrigé et écart préexistant de contexte laissé inchangé |
| `before-parallel-guard/` | Premier candidat qualifié puis écarté : ralentissement confirmé sur le fichier intermédiaire |

Les suites maintenues sont dans [`../../tests/binary-output.py`](../../tests/binary-output.py),
[`../../bench/compare.py`](../../bench/compare.py) et `bench/internal.*`.
Le nouveau test binaire fait partie de `zig build test` pour `zgrc` et de
`zig build test-zpcre2-gnu` pour `zgr`. Il compare stdout, stderr normalisé et
le code de retour à GNU grep, en locales C et C.UTF-8, ainsi que les entrées
régulières redirigées sur stdin. Les cas couvrent les frontières de blocs de
96 Kio, les lignes longues, les mots rejetés, les octets invalides et les
dernières lignes sans terminateur. Le contexte, les couleurs et `-o` restent
dans les suites existantes, hors du nouveau chemin.

## Reproduction

Utiliser Zig 0.16.0, ReleaseFast et LLVM, avec les dépendances verrouillées.
Préserver une construction de `cbed1de` dans un dossier distinct de celle du
candidat. Les captures locales indiquent leurs chemins absolus ; adapter ces
chemins, sans réutiliser un ancien nom de sortie JSON.

```sh
zig build install bench-internal -Doptimize=ReleaseFast -Dllvm=true --prefix /tmp/candidat
bench/generate.sh /tmp/corpus.txt 1000000 newline
python3 docs/performance-binary-output-2026-11-11/compare-output.py \
  --root "$PWD" --baseline /tmp/reference/bin/zgr --candidate /tmp/candidat/bin/zgr \
  --corpus /tmp/corpus.txt --suite output --cpu 2 --repeats 25 \
  --output /tmp/sortie-binaire.json
python3 tests/binary-output.py /tmp/candidat/bin/zgr
```

Ajouter `--locale C.UTF-8`, `--input-mode text`, ou `--cpu 2,4,6,8` pour les
contrôles correspondants. Choisir des CPU autorisés sur la machine. Le corpus
intermédiaire se génère avec `200000` lignes au lieu d'un million, et le petit
corpus avec `80000` lignes.

Pour comparer le treizième microbenchmark, copier le `bench/internal.zig`
actuel dans la copie isolée de `cbed1de`, puis y construire `bench-internal`.
Le harnais détecte la présence de la nouvelle fonction : dans la référence,
il appelle les fonctions réelles de préanalyse NUL puis de sortie séquentielle.
Le nouveau noyau utilise un tampon ASCII sans NUL et un seul CPU ; il mesure
la recherche, la détection et le formatage ensemble, sans processus ni E/S.
Son temps ne doit pas être additionné aux autres noyaux.

`final-measurements.py` décrit la disposition locale utilisée et exécute les
séries sans chevauchement. Ne pas lancer de compilation ou de tests pendant
les mesures. L'environnement utilise des fichiers chauds et une fréquence CPU
non verrouillée ; comparer les tours appariés, pas deux campagnes éloignées.

## Écarts préexistants distingués du correctif

Les lots `test` et `test-fuzz` passent. Les contrôles supplémentaires du moteur
zpcre2 échouent sur l'alternance BRE avec `-o` et sur le pliage de casse accentuée.
Ces deux échecs ont été reproduits avec le binaire intact de `cbed1de`, puis
avec le candidat final. Le premier lot global `test-zpcre2-gnu` conserve son
statut d'échec dans `before-parallel-guard/qualification-fast.log` ; le lot
principal final réussi ne constitue pas une validation GNU complète de zpcre2.

`edge-findings.json` montre aussi qu'avec `-C1`, un NUL placé exactement à
96 Kio peut faire perdre une ligne de contexte : la référence et le candidat
ont la même sortie. Ce cas ne passe pas par le nouveau chemin et n'est pas
corrigé ici. La fixture est `end-98303-nul-98304` dans `fixtures()` du test
binaire ; les options et sorties sont enregistrées dans le JSON.

Le diagnostic binaire doublé après une ligne sélectionnée en UTF-8 invalide,
puis un NUL plus loin, est en revanche corrigé et vérifié face à GNU grep.
La fixture correspondante figure dans le même fichier de preuves.

## Essai écarté

La première version conservait seulement le chemin de sortie parallèle au-delà
de 64 Mio. Elle remplaçait encore la détection NUL parallèle entre 16 et 64 Mio.
Sur 18,8 Mo et quatre CPU, le contrôle à 61 tours a confirmé environ 5 % de
temps supplémentaire pour la sortie rare numérotée et 2,6 % pour la sortie
dense simple. Les sources, empreintes, échantillons et validations de cet essai
restent dans `before-parallel-guard/`.

Le correctif final conserve donc la détection existante dès qu'elle peut
utiliser plusieurs workers : fichier supérieur à 16 Mio et plusieurs CPU
disponibles. Le nouveau chemin est admissible sur un cœur quelle que soit
la taille, ainsi que sur les fichiers de 96 Kio à 16 Mio avec plusieurs CPU.
