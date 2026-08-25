# zgrep v0.2 — petit benchmark comparatif

Mesure capturée le 2026-08-25 à 10:59 CEST sur Linux 6.8.0 x86_64,
Intel Core i9-13900KF (32 CPU logiques), avec Zig 0.16.0, GNU grep 3.11 et
ripgrep 15.2.0. Le corpus est
`/usr/src/linux-headers-6.8.0-137` : 16 280 fichiers et 72 622 832 octets.

## Artefacts comparés

- zgrep v0.2, implémentation `664e71a` :
  `a8b945c0aa73fce524f594a97da2e5ff83cbf5dc6459192b5ec422e17f31ee66` ;
- baseline avant capture exacte, commit `7179e03` :
  `272c95ba4bbed93a02524c523b93dfc5b7f1d3cccc5d62f22c78f33a33a390cf` ;
- ripgrep 15.2.0, révision `e89fff89ac`.

## Méthode

- cache chaud, `LC_ALL=C`, `taskset -c 0-15` ;
- 9 batches interleavés de 5 exécutions par outil et par mode ;
- médiane exprimée en millisecondes par exécution ;
- stdout redirigé vers un fichier régulier, jamais `/dev/null` ;
- avant chaque mesure, les sorties triées de zgrep et ripgrep sont comparées à
  GNU grep ; l'ordre GNU exact de zgrep est couvert séparément par le stress
  récursif.

Les trois familles sont : littéral dense `CONFIG_`, littéral sparse
`PM_RESUME`, et regex sans littéral
`[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}[[:space:]]+[[:alnum:]_]{5}`. Le benchmark exécute les
formes récursives liste (`-r -l`) et sortie ordinaire (`-r -n`).

## Médianes

| Famille | Mode | zgrep v0.2 | baseline `7179e03` | ripgrep |
|---|---|---:|---:|---:|
| littéral dense | liste | 15,718 | 15,741 | 18,036 |
| littéral dense | sortie | 19,056 | 22,773 | 20,366 |
| littéral sparse | liste | 15,565 | 15,443 | 15,419 |
| littéral sparse | sortie | 15,501 | 15,431 | 15,297 |
| regex sans littéral | liste | 19,975 | 19,617 | 21,129 |
| regex sans littéral | sortie | 20,166 | 20,225 | 21,421 |

Sur la cible principale, la sortie littérale dense, v0.2 améliore la baseline
de 16,3 % et devance ripgrep de 6,4 %, tout en conservant l'ordre de parcours
GNU. Les contrôles sparse et sans littéral restent proches de la baseline ; ce
petit échantillon ne constitue pas une affirmation universelle entre machines,
systèmes de fichiers ou caches froids.

Pour rejouer le profil public courant sans baseline A/B :

```sh
BENCH_PROFILE=ripgrep-linux-default BENCH_BATCHES=9 BENCH_CPUSET=0-15 \
  BENCH_LOCALE=C ZGREP=./zig-out/bin/zgrep \
  bench/run-tree.sh /usr/src/linux-headers-6.8.0-137 PM_RESUME 5
```
