# Cursor grep contre zgr

[English](cursor-grep-comparison.md) | [Français](cursor-grep-comparison.fr.md)

Mesure capturée le 2026-08-29 à 14:00 CEST sur Linux 6.8.0-138-generic x86_64,
avec un Intel Core i9-13900KF (32 CPU logiques), Zig 0.16.0, GNU grep 3.11 et
le ripgrep fourni par Cursor, 15.1.0-cursor5 (révision `c3e3c2f7ec`). Le
corpus fichier a été généré par `bench/generate.sh` avec 100 000
enregistrements : 9 378 980 octets et SHA-256
`1dcecb7edb774134592782760c18b6d8f09fc91b2cc9f6463bfd85cc77b75c45`.

Il s'agit d'un échantillon à cache chaud, sur un petit arbre, de la Grep
agent de Cursor face à `zgr`. Il ne permet pas de conclusions universelles
entre machines, systèmes de fichiers ou caches froids.

## Artefacts comparés

- Cursor Grep : l'outil de recherche de l'agent, une enveloppe JSON autour
  d'un `rg` embarqué. Le binaire chronométré est ce ripgrep, pas la couche
  RPC de l'agent.
- Cursor `rg` 15.1.0-cursor5, lié statiquement, 5 396 392 octets, fonctions
  `+pcre2`, PCRE2 10.45 avec JIT. SIMD à l'exécution : SSE2, SSSE3, AVX2.
- `zgr` 0.3.1 (zpcre2 par défaut), ReleaseFast de cet arbre à `8769176`, lié
  dynamiquement à libc, 831 688 octets :
  `3797160790268324f309dc73839bf7b0edc6b0917bd4f145335027b75f2d9020`
- `zgrc` 0.3.1 (compat GNU, PCRE2 JIT en C), 461 720 octets :
  `239e37ffe76c0bffec11e61c59bc59eb483d55611f4376cea7d782b16227171f`
- GNU grep 3.11

## Méthode

- cache de pages chaud, `LC_ALL=C`, CPU non restreint
- cas d'arbre : médiane de 9 exécutions ; cas fichier : médiane de 5
  exécutions
- stdout redirigé vers un fichier ordinaire, jamais vers `/dev/null`
- Cursor `rg` a conservé ses règles d'ignore par défaut (gitignore, fichiers
  cachés, binaires) sauf mention contraire
- les exécutions « équitables » de `zgr` / GNU grep sur l'arbre passaient
  `--exclude-dir=.git --exclude-dir=.zig-cache --exclude-dir=zig-out`
- les outils compatibles GNU ont utilisé `-F` / `-E` / `-P` pour coller à
  chaque mode ripgrep ; ripgrep a utilisé sa syntaxe regex par défaut, sauf
  `-P` explicite

Rejouer :

```sh
zig build -Doptimize=ReleaseFast
BENCH_BATCHES=1 TREE_PATTERN=Matcher \
  bench/run-cursor-rg.sh . 9
```

Surchargez le binaire ripgrep avec `CURSOR_RG`. Sans Cursor, le script
utilise `rg` depuis `PATH`. Définissez `CORPUS` pour réutiliser un fichier
généré, ou laissez le script appeler `bench/generate.sh` (100 000
enregistrements par défaut).

```sh
bench/generate.sh /tmp/zgrep-cursor-rg-bench.txt 100000
CORPUS=/tmp/zgrep-cursor-rg-bench.txt BENCH_BATCHES=1 \
  bench/run-cursor-rg.sh . 5
```

## Ce qui change hors performance

La Grep agent de Cursor est faite pour donner à un agent des hits dans une
copie git. `zgr` est fait pour suivre GNU grep. Les défauts qui comptent :

| Capacité | Outil Grep Cursor | CLI `rg` Cursor | `zgr` |
|---|---|---|---|
| Syntaxe par défaut | regex Rust | regex Rust | BRE (`-E` / `-F` / `-P`) |
| Récursion | toujours | par défaut | seulement avec `-r` / `-R` |
| gitignore / cachés | actif, non optionnel dans le schéma de l'outil | actif, surchargeable | inactif |
| Fichiers binaires | ignorés | ignorés | GNU `binary` / `text` / `-I` / `-a` |
| Plafond de résultats | quelques milliers de lignes | aucun | aucun |
| `-F` / `-P` | absent du schéma de l'outil | oui | oui |
| Type / glob | `glob` et `type` | globs et types rg | `--include` / `--exclude` / `--exclude-dir` |

Sur ce dépôt, cet écart pèse plus que le moteur. L'arbre fait environ
2,4 Mio de sources à côté d'un `.zig-cache` de 1,3 Gio. Cursor `rg --files`
a parcouru 36 chemins. `find` en a parcouru 780. `zgr -r` sans exclusions a
cherché dans le cache.

## Résultat sur l'arbre

Motif `Matcher` avec numéros de ligne, ce dépôt au moment de la capture.

| Outil | Médiane | Fichiers | Lignes | Ce qui a été parcouru |
|---|---:|---:|---:|---|
| cursor rg (défaut) | 3,568 ms | 5 | 137 | 36 fichiers visibles via gitignore |
| zgr `-r`, caches exclus | 1,774 ms | 5 | 137 | 133 fichiers hors git/cache/out |
| GNU grep `-r`, mêmes exclusions | 3,145 ms | 5 | 137 | les mêmes 133 fichiers |
| zgr `-r` (récursif GNU) | 51,004 ms | 62 | 137 | 780 fichiers, dont 1,3 Gio de cache |

`src/` seul, sans règles d'ignore :

| Outil | Médiane |
|---|---:|
| zgr `-r src` | 0,846 ms |
| GNU grep `-r src` | 1,153 ms |
| cursor rg `src` | 3,407 ms |

Sur un tout petit arbre, le démarrage du processus et l'évaluation des
règles d'ignore dominent Cursor `rg`. L'écart de 14× sur la récursion
complète, c'est `zgr` qui lit le cache Zig, pas un moteur plus lent.

## Résultat sur fichier généré

Corpus `/tmp/zgrep-zpcre2-bench.txt`, 100 000 lignes. Temps en millisecondes
par exécution. Plus bas est mieux. GNU grep n'a pas `-P` sur cette machine.

| Charge | cursor rg | zgr | zgrc | GNU grep | Gagnant |
|---|---:|---:|---:|---:|---|
| absence littérale `-c` | 2,355 | 2,896 | 2,877 | 3,378 | cursor rg |
| littéral rare `-c` | 2,244 | 2,043 | 2,018 | 4,463 | zgrc |
| mot `-cw` | 2,634 | 1,792 | 1,919 | 4,235 | zgr |
| insensible à la casse `-ci` | 3,840 | 2,111 | 2,079 | 4,238 | zgrc |
| ERE `status=(200\|500)` `-c` | 5,493 | 3,396 | 3,098 | 9,538 | zgrc |
| ERE à littéral interne `-c` | 6,325 | 2,805 | 3,390 | 9,298 | zgr |
| sortie littérale `-n` | 2,372 | 2,117 | 1,886 | 4,740 | zgrc |
| PCRE `latency_us=\d+` `-c` | 7,085 | 6,730 | 3,253 | n/a | zgrc |

Les comptes concordent là où ils ont été comparés : 100 hits `rare-needle`
et 100 000 hits `status=(200|500)`.

Sur un fichier nommé, `zgr` / `zgrc` gagnent toutes les charges sauf
l'absence littérale. `zgrc` est le plus rapide sur le compte PCRE dense,
c'est-à-dire PCRE2 JIT en C plutôt que zpcre2.

## Dialecte

Cursor `rg` utilise la regex Rust, donc `|` est une alternance. `zgr` est en
BRE par défaut, donc `|` est un tube littéral. Recherche de `error|warning`
dans `src/` :

| Outil | Hits |
|---|---:|
| cursor rg | 203 |
| zgr (BRE) | 1 |
| zgr `-E` | 203 |

Passez `-E` (ou `-F` / `-P`) avant de traiter un motif ripgrep comme un
motif `zgr`.

## Lecture du résultat

Cursor grep est le meilleur défaut dans une copie git : il cherche les 36
fichiers qui intéressent un agent et n'ouvre jamais `.zig-cache`. `zgr` est
le meilleur scanner de forme GNU sur un fichier nommé, ou sur un arbre dont
on a déjà exclu les déchets. Pointez `zgr -r` sur ce dépôt sans
`--exclude-dir` et il cherchera correctement, et lentement, dans le cache.
