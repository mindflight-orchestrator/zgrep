# Compilation Zig, LLVM et comparaison Rust/C — 11 novembre 2026

[English](benchmark-backends.md) | [Données et scripts](benchmark-backends-2026-11-11/README.md)

Pour privilégier le temps d'exécution de `zgr`, le profil retenu est **Zig
0.16.0, ReleaseFast, LLVM**. Le backend x86 propre à Zig compile beaucoup plus
vite dans cette expérience, mais produit un exécutable nettement plus lent.
La comparaison demandée face à Rust et C a ensuite été exécutée avec les
binaires LLVM : `zgr` devance GNU grep sur les 12 cas mesurés ; ripgrep conserve
l'avantage sur plusieurs recherches littérales et la sortie peu dense.

## Paramètres et sens de « natif »

```sh
zig build -Doptimize=ReleaseFast -Dllvm=true -Dcpu=native
zig-out/bin/zgr --version
```

Dans ce dépôt, `zig build` sans option utilise Debug ; `make` utilise
ReleaseFast par défaut. Les anciens scripts de benchmark exécutaient le binaire
présent, sans contrôler sa compilation. Le mode d'un ancien résultat ne peut
donc pas être déduit du seul nom du script.

`ReleaseFast` privilégie les optimisations et désactive par défaut les contrôles
de sûreté à l'exécution. C'est le mode adapté à cette comparaison après les tests
fonctionnels. [Référence Zig 0.16](https://ziglang.org/documentation/0.16.0/#Build-Mode).

`-Dllvm=true` est désormais une option explicite du projet, transmise aux
exécutables et aux tests Zig. Elle correspond à `-fllvm` pour une invocation
directe du compilateur. `-Dllvm=false` sélectionne le backend propre à Zig.
`-Dcpu=native` choisit les instructions du processeur local, indépendamment du
backend ; ce choix convient à une mesure locale, mais ne garantit pas la
compatibilité avec une machine plus ancienne.

Les deux backends produisent du code machine natif. LLVM ajoute son travail
d'optimisation à la compilation ; il n'y a pas de machine virtuelle LLVM au
lancement. Dans les notes Zig 0.15.1, le backend x86 est présenté comme un gain
de vitesse de compilation, avec du code machine alors plus lent et un usage
orienté développement. C'est un contexte historique, que les mesures locales
ci-dessous vérifient séparément pour 0.16.0 et 0.17.0.
[Notes officielles, backend x86](https://ziglang.org/download/0.15.1/release-notes.html#x86-Backend).

Il n'existe pas de paramètre garantissant l'exécution la plus rapide pour tous
les programmes. Le profil ci-dessus est celui étayé ici ; LTO, PGO et les autres
modèles de CPU n'ont pas été comparés. Supprimer les symboles est déjà prévu par
le projet en ReleaseFast et ne constitue pas, à lui seul, une optimisation des
boucles de recherche.

## Expérience 1 : Zig 0.16 et 0.17, LLVM et backend natif

Base : commit `a373c95b99e1c5fd9f5a8b7001c82a296db96d88`, dépendance zpcre2
`b93f4d8d999f1f000ecc3644c844294802ba78bb`. Les deux exécutables, `zgr` et
`zgrc`, ont été compilés dans des copies isolées pour chaque variante.
Les commandes locales `zig-0.16 version` et `zig-0.17 version` ont renvoyé
respectivement `0.16.0` et `0.17.0`.

La copie 0.17 a nécessité des adaptations de syntaxe et d'API, conservées dans
[le patch de compatibilité](benchmark-backends-2026-11-11/zig-017-compatibility.patch).
Cette expérience ne qualifie pas une migration du dépôt vers 0.17 ; le projet
et sa CI restent sur 0.16.0.

Extraits pour `zgr`, temps médians, plus petit = plus rapide :

| Variante | Compilation de zgr (s) | Littéral rare (ms) | Regex dense (ms) |
|---|---:|---:|---:|
| Zig 0.16 LLVM | 5,82 | 1,566 | 2,374 |
| Zig 0.16 natif | 0,26 | 119,094 | 177,870 |
| Zig 0.17 LLVM | 5,92 | 1,406 | 2,559 |
| Zig 0.17 natif | 0,26 | 120,347 | 182,325 |

La compilation mesure trois invocations `build-exe` par variante, avec cache
local neuf, cache global d'infrastructure déjà préparé et `-j2`, dans un ordre
aléatoire séquentiel. Elle exclut la compilation du programme de build et
`translate-c`. Les premiers builds complets avaient des états de cache
différents et ne servent pas à cette comparaison. Les temps courts sont
arrondis à cause de la granularité d'attente du processus de mesure.

L'exécution utilise 100 000 lignes ASCII, soit 9 378 980 octets, la locale C,
le CPU logique 2 d'un i9-13900KF, des données en cache et une sortie vers un
fichier ordinaire. Chaque variante a deux échauffements et quinze mesures par
cas, avec ordre aléatoire apparié. Les 1 360 vérifications de sortie et de statut
ont réussi pour les deux exécutables et les dix cas.

LLVM est très nettement devant le backend natif sur ces charges. En revanche,
ces données ne démontrent pas de gain général de 0.17 LLVM sur 0.16 LLVM : les
écarts dépendent du cas et les mesures proches du coût de lancement sont
sensibles au bruit. Les douze recompilations ont aussi passé le contrôle du
littéral rare ; les binaires LLVM reproduisaient leurs empreintes, les binaires
du backend natif ne les reproduisaient pas tous.

Sources : [exécution](benchmark-backends-2026-11-11/benchmark-results.json),
[compilation](benchmark-backends-2026-11-11/compile-results.json),
[recompilations](benchmark-backends-2026-11-11/recompile-validation.json).

## Pourquoi cet écart d'exécution ?

Deux petites fonctions ont été isolées avec Zig 0.16 : `isAscii`, extraite de
`src/matcher.zig`, et une recherche du premier octet nul via
`std.mem.findScalar`. Même pilote C, même tampon de 9 378 980 octets déjà en
mémoire, aucun accès disque dans la mesure, deux échauffements et quinze passes.

| Fonction | LLVM (ms) | Backend natif (ms) |
|---|---:|---:|
| Vérifier ASCII | 0,224 | 13,441 |
| Rechercher un octet nul absent | 0,143 | 10,488 |

L'assembleur LLVM de `is_ascii` utilise notamment `vmovdqu` et `vpmovmskb` pour
traiter des groupes de 32 octets. Le backend natif passe par des écritures sur
la pile et une boucle de comparaisons octet par octet pour construire le
masque. Écrire un vecteur dans le source Zig ne garantit donc pas la même
qualité de code machine avec chaque backend.

Cela démontre une différence concrète de génération de code sur des primitives
utilisées par la recherche. Ce microbenchmark n'attribue pas la totalité de
l'écart du programme à ces deux fonctions : cette attribution nécessiterait
un profilage complet. [Sources, assembleur et mesures](benchmark-backends-2026-11-11/kernels/).

## Expérience 2 : candidat LLVM face à ripgrep et GNU grep

**Précision de l'audit suivant :** cette capture passait `-a` à ripgrep seul.
La détection binaire ajoutait donc du travail à `zgr` pour les sorties de
lignes ; le chemin `-c` de `zgr` évite déjà cette préanalyse. Les données brutes
restent inchangées. L'[audit des chemins lents](performance-audit.fr.md) présente
les nouvelles mesures avec options équivalentes (`auto` ou `-a` pour tous).
La section [Temps total et comparaison](performance-audit.fr.md#temps-total-et-comparaison)
met côte à côte `zgr`, ripgrep et GNU grep, puis explique précisément les
6,3 ms de comptage, 3,6 ms de détection binaire et 1 ms de numérotation mesurés
en interne : ces chiffres ne sont pas les parts d'un même temps total.
Le même rapport présente en tête la détection binaire progressive pour les
sorties littérales, puis le comptage adaptatif, avec leurs résultats face à
Rust/C et leurs limites mesurées.

Cette deuxième mesure utilise les sources du dépôt avec les adaptations du
benchmark et les métadonnées de compilation. Elle repose sur le même commit
de base, avec des changements locaux ; les empreintes des entrées de compilation
sont enregistrées dans le JSON. Ce n'est pas un nouveau tag publié.

| Outil | Version / compilation |
|---|---|
| zgr | 0.4.1, Zig 0.16.0, ReleaseFast, stage2_llvm, CPU raptorlake, zpcre2 |
| zgrc | 0.4.1, même profil Zig, moteur C PCRE2/glibc |
| ripgrep | 15.2.0, révision e89fff89ac, exécutable Rust installé, AVX2 détecté à l'exécution |
| GNU grep | 3.11, exécutable C installé, référence fonctionnelle |

`zgrc` contient du Zig et un moteur C ; la référence C externe est GNU grep.
Les options de compilation originales de ripgrep et GNU grep ne sont pas
connues ici. Il s'agit d'une comparaison d'outils et d'algorithmes, pas d'une
mesure isolée des langages Rust, C et Zig.

Corpus : 1 000 000 lignes, **93 789 827 octets**, généré par `bench/generate.sh`.
Locale C, CPU logique 2, tous les threads héritant de cette affinité : cette
mesure ne caractérise pas le débit sur plusieurs cœurs. Deux échauffements puis
quinze tours dans un ordre aléatoire, graine 711. Le temps inclut le lancement
du processus et l'écriture dans un fichier temporaire, sans `fsync`, avec les
données en cache. Il ne mesure ni le disque à froid ni l'affichage sur terminal.

Médianes en millisecondes, plus petit = plus rapide :

| Cas | zgr LLVM | zgrc LLVM | ripgrep (Rust) | GNU grep (C) |
|---|---:|---:|---:|---:|
| Littéral absent | 15,655 | 16,246 | 13,980 | 25,659 |
| Littéral rare | 15,948 | 16,495 | 14,069 | 36,450 |
| Littéral sans distinction de casse | 15,306 | 13,570 | 15,219 | 35,036 |
| Mot entier | 15,815 | 16,393 | 13,732 | 35,793 |
| Regex dense | 29,140 | 28,996 | 63,717 | 90,879 |
| Regex avec suffixe littéral | 13,940 | 13,737 | 13,652 | 43,443 |
| Alternance | 33,311 | 33,301 | 33,286 | 119,999 |
| Regex sans littéral | 33,783 | 33,587 | 62,111 | 58,814 |
| Sortie numérotée peu dense | 19,392 | 16,465 | 13,131 | 39,317 |
| Sortie numérotée dense | 58,144 | 58,336 | 165,480 | 89,624 |
| Sortie dense sans numéros | 44,538 | 44,658 | 83,510 | 56,999 |
| Sortie regex numérotée | 24,902 | 33,628 | 54,199 | 86,136 |

Les **816 exécutions contrôlées**, dont 720 chronométrées, concordent avec GNU
grep en code retour, taille et SHA-256 de sortie. Les commandes exactes,
échantillons, empreintes des exécutables et intervalles bootstrap à 95 % des
ratios appariés sont conservés dans
[comparison-llvm-rust-c.json](benchmark-backends-2026-11-11/comparison-llvm-rust-c.json).
Un ratio supérieur à 1 y signifie que le binaire Zig est plus rapide que la
référence. La médiane des ratios appariés peut différer du rapport des médianes
affichées ci-dessus. Les écarts minuscules ne justifient pas de classer les outils.

## Reproduire et contrôler une publication

Sur Linux avec Python 3.11+, Zig 0.16.0, ripgrep, GNU grep et les dépendances
du projet :

```sh
zig build -Doptimize=ReleaseFast -Dllvm=true -Dcpu=native
zig build test -Doptimize=ReleaseFast -Dllvm=true
bench/generate.sh /tmp/zgrep-comparison.txt 1000000
python3 bench/compare.py --corpus /tmp/zgrep-comparison.txt \
  --cpu 2 --repeats 15 --output /tmp/zgrep-comparison.json
```

Choisir un CPU autorisé sur la machine et un nouveau chemin JSON à chaque
exécution. Sans `--cpu`, l'affinité existante est conservée. Les options `--zgr`,
`--zgrc`, `--rg`, `--grep` permettent de sélectionner explicitement les binaires.
Le comparateur utilise le profil ASCII newline généré ; les arbres, NUL,
Unicode et entrées en flux disposent d'autres tests et benchmarks.

`--version` déclare désormais la version Zig réelle, le mode, le backend et le
modèle CPU. Tous les lanceurs de benchmark vérifient ReleaseFast + LLVM avant
les mesures. `BENCH_ALLOW_UNOPTIMIZED=1` autorise une exploration explicitement
signalée, également enregistrée dans le JSON. Un résultat existant est préservé.

La CI et le workflow de release construisent explicitement avec LLVM et
comparent les quatre outils sur 100 000 lignes et trois tours. Le workflow de
release place le JSON dans l'archive distribuée. Une sortie incorrecte bloque
la préparation de l'archive ; aucun seuil de vitesse ne bloque une release
sur un runner partagé.

Validation locale : 82/82 tests unitaires, différentiels CLI et streaming,
59 cas regex et 141 cas de locales réussis ; contrôle des profils Debug,
natif, LLVM et ancien binaire réussi ; comparaison C.utf8 à trois tours et
benchmark shell existant réussis. Les logs sont dans le dossier de preuves.
Les workflows GitHub modifiés n'ont pas été exécutés à distance dans cette
recherche. Ces résultats constituent une validation locale ; aucun tag, push
ou publication n'a été effectué pour ce lot.
