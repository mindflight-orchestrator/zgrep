# zgr vs zgrc — comparaison sur corpus généré

[English](benchmark-zgr-zgrc.md) | [Français](benchmark-zgr-zgrc.fr.md)

Mesure capturée le 29 août 2026 à 14:05 CEST sur Linux 6.8.0-138 x86_64,
avec un Intel Core i9-13900KF (32 CPU logiques), Zig 0.16.0, zpcre2
[v0.5](https://github.com/mindflight-orchestrator/zpcre2/releases/tag/v0.5),
GNU grep 3.11 et ripgrep 15.1.0. Le corpus a été généré par
`bench/generate.sh` avec 100 000 enregistrements à saut de ligne : 9 378 980
octets et SHA-256
`1dcecb7edb774134592782760c18b6d8f09fc91b2cc9f6463bfd85cc77b75c45`.

## Artefacts comparés

Binaires ReleaseFast de cet arbre :

- `zgr` (défaut, zpcre2 v0.5) :
  `3797160790268324f309dc73839bf7b0edc6b0917bd4f145335027b75f2d9020` ;
- `zgrc` (compatibilité GNU, JIT PCRE2 C + regex glibc) :
  `239e37ffe76c0bffec11e61c59bc59eb483d55611f4376cea7d782b16227171f` ;
- GNU grep 3.11 ;
- ripgrep 15.1.0 (`c3e3c2f7ec`).

`zgrc` n'est jamais retiré. Le profil généré chronomètre les deux binaires et
échoue si l'un des deux diffère de GNU grep.

## Méthode

- cache chaud, `LC_ALL=C`, CPU non restreint ;
- 5 exécutions par outil et par cas, stdout redirigé vers un fichier ordinaire ;
- chaque cas comparé à GNU grep avant le chronométrage ; **`zgr` et `zgrc`
  correspondent sur tous les cas du profil généré**, y compris l'ERE dense
  `status=(200|500)` et le littéral interne
  `route=/api/item/[[:digit:]]+[[:space:]]+status=500`.

```sh
zig build -Doptimize=ReleaseFast
bench/generate.sh /tmp/zgrep-zgr-zgrc-bench.txt 100000
BENCH_BATCHES=1 BENCH_LOCALE=C \
  ZGR=./zig-out/bin/zgr ZGRC=./zig-out/bin/zgrc \
  bench/run.sh /tmp/zgrep-zgr-zgrc-bench.txt 5
```

Il s'agit d'un échantillon ASCII sur fichier généré, pas du profil d'arbre
récursif. Il ne justifie pas de conclusions universelles entre machines,
systèmes de fichiers ou caches froids. Il n'exerce **pas** les écarts GNU
expérimentaux listés plus bas.

## Temps

Millisecondes par exécution. Plus bas est mieux. Le ratio est `zgr / zgrc`
(zpcre2 / C).

| Charge | zgr | zgrc | grep | ripgrep | zgr / zgrc |
|---|---:|---:|---:|---:|---:|
| absence littérale | 2,306 | 2,622 | 4,400 | 3,308 | 0,88× |
| occurrence littérale rare | 2,273 | 2,273 | 4,457 | 2,716 | 1,00× |
| littéral insensible à la casse | 2,370 | 2,506 | 5,234 | 3,879 | 0,95× |
| littéral de mot | 2,633 | 2,415 | 4,359 | 3,302 | 1,09× |
| **regexp étendue** `status=(200\|500)` | 3,454 | 3,817 | 8,324 | 6,964 | **0,90×** |
| regexp à suffixe littéral | 2,062 | 2,152 | 5,681 | 2,979 | 0,96× |
| alternance littérale | 4,299 | 4,184 | 11,924 | 5,336 | 1,03× |
| alternance littérale insensible à la casse | 8,895 | 8,320 | 11,071 | 13,270 | 1,07× |
| **regexp à littéral interne** | 5,405 | 6,806 | 11,746 | 7,866 | **0,79×** |
| regexp sans littéral | 3,523 | 3,299 | 7,365 | 7,685 | 1,07× |
| sortie littérale `-n` | 2,530 | 2,470 | 4,941 | 2,796 | 1,02× |
| sortie littérale en mode texte | 2,120 | 2,342 | 5,287 | 2,855 | 0,91× |
| sortie regexp à suffixe `-n` | 2,886 | 2,831 | 6,580 | 3,145 | 1,02× |
| sortie segments correspondants | 3,055 | 2,774 | 6,377 | 3,040 | 1,10× |
| sortie d'alternance littérale `-n` | 5,731 | 5,920 | 13,426 | 7,547 | 0,97× |
| sortie littérale segments | 2,265 | 2,286 | 5,068 | 3,121 | 0,99× |
| sortie littérale colorée | 2,482 | 2,518 | 5,488 | — | 0,99× |
| sortie regexp colorée | 3,205 | 2,940 | 6,534 | — | 1,09× |
| sortie littérale avec contexte | 2,353 | 2,481 | 5,288 | 2,933 | 0,95× |
| sortie regexp avec contexte | 2,775 | 2,802 | 6,135 | 3,702 | 0,99× |
| littéral rare depuis stdin | 4,774 | 5,061 | 5,238 | 6,059 | 0,94× |

La moyenne géométrique non pondérée de `zgr / zgrc` sur les 21 charges
chronométrées est **0,98×**. L'ERE dense est désormais à parité ou en faveur
de zpcre2 (0,90×) ; le littéral interne reste en tête (0,79×). Les parcours
littéraux restent proches de la parité car les deux binaires partagent le
scanner Zig.

Un essai sur le même corpus en `C.utf8` a aussi concordé avec GNU grep pour
les deux binaires avant chronométrage. Cette locale ne couvre toujours pas
les écarts Unicode ci-dessous : le fichier généré est ASCII.

## Contrôles de test sur cette capture

| Étape | Binaire | Résultat |
|---|---|---|
| `zig build test -Doptimize=ReleaseFast` | diffs GNU de `zgrc` + tests unitaires des deux moteurs | réussi (CLI, 59 regex, 141 locales UTF-8) |
| `zig build test-zpcre2` | unités de `zgr` | réussi |
| `zig build test-fuzz` (`ZGREP_FUZZ_ITERATIONS=256`) | `zgrc` | réussi (3072 contrôles) |
| `zig build test-stress` | `zgrc` | réussi |
| bench du profil généré | `zgr` et `zgrc` | réussi, tous les cas chronométrés |
| `zig build test-zpcre2-gnu` | `zgr` face à GNU | **échec** (expérimental ; inventaire ci-dessous) |

Le fuzz et le stress sont des contrôles de compatibilité GNU sur **`zgrc`**.
Ils ne sont pas revendiqués pour `zgr`.

## Écarts GNU expérimentaux de `zgr`

`zgr` (zpcre2 + `locale.zig` en Zig) est le binaire par défaut. Ce n'est **pas**
un équivalent GNU pour tout BRE/ERE/locale. `zig build test-zpcre2-gnu` reste
expérimental et n'est pas un contrôle d'intégration continue. Le script
différentiel CLI **réussit** contre `zgr` ; les échecs portent sur la sémantique
regex et la locale UTF-8.

Inventaire sur le même `zgr` ReleaseFast que le bench, en poursuivant après le
premier écart pour lister tous les cas. Le statut est GNU grep → `zgr`.

### Sémantique regex : 27 / 59 échecs

POSIX gauche-le-plus-tôt/plus-long en `-o` (statut 0, segments trop courts ou
faux). zpcre2 est gauche-premier, pas GNU plus-long :

- BRE groupement et alternance `\(a\|ab\)c\?` ;
- BRE rétro-référence ambiguë `\(a\|aa\)\1` ;
- ERE alternance imbriquée la plus longue `(a|ab)c?` ;
- ERE suffixe imbriqué le plus long `a(b|bb)c?` ;
- ERE plus long segment à motifs multiples ;
- ERE intervalle en tête d'expression `{2}a`.

GNU accepte le motif, zpcre2 le refuse (0 → 2) :

- intervalle inférieur ouvert BRE / ERE `a\{,2\}` / `a{,2}` ;
- répétition BRE en tête `*a` ;
- `)` et `a)` ERE non appariés ;
- étoile / plus / interrogation ERE en tête ;
- étoile ERE en tête de groupe `(*a)`.

GNU refuse avec une erreur fatale, zpcre2 non (2 → 1) :

- répétition BRE / ERE au-dessus de la limite GNU `{32768}`.

Limites de mot GNU absentes (`\<` / `\>`, 0 → 1, aucune correspondance) :

- limites de mot GNU BRE ;
- limite de mot GNU ERE.

GNU traite les échappements PCRE comme des littéraux en BRE/ERE ; zpcre2 non :

- `\d` est littéral pour GNU, une classe de chiffres pour `zgr` ;
- `\n` est littéral pour GNU (0 → 1) ;
- `[\d]` conserve un antislash ordinaire pour GNU.

Autres divergences de syntaxe PCRE/GNU :

- ERE `(?=a)` n'est pas une assertion pour GNU (aucune correspondance, 1) ;
  zpcre2 correspond (0) ;
- ERE `a+?` est un `+` GNU répété puis un `?` littéral ; zpcre2 l'analyse comme
  paresseux (statut 0, segments différents).

### Locale UTF-8 : 60 / 141 échecs

Les mêmes 20 cas échouent dans `C.utf8`, `en_US.utf8` et `nl_BE.utf8`.
`locale.zig` lit l'UTF-8 depuis `LC_*` et utilise `std.ascii` pour les classes
d'octets. Il n'implémente pas `wctype` libc, le repli de casse Unicode ni les
limites de mot larges GNU.

Repli de casse Unicode (chaîne fixe et ERE `-i`) :

- repli de casse fixe accentué / grec / ligne entière ;
- repli de casse ERE accentué `^école$`.

Limites de mot Unicode / GNU :

- limite de mot fixe accentuée, limite CJK à droite, mot CJK ;
- limite GNU ERE accentuée `\<é\>` ;
- alternatives de mot entier ERE ;
- limites de mot Unicode ASCII fixes en récursif.

Classes POSIX / PCRE hors ASCII :

- ERE `[[:upper:]]`, `[[:alpha:]]`, `[[:alpha:]]` inversé, comptage
  `[[:alpha:]]+` ;
- PCRE `\p{L}+` ;
- témoin regex Unicode `[[:alnum:]_]{12}` et la forme de classe niée.

Segments d'enregistrements UTF-8 invalides (`.` avec `-o`) :

- segments ERE UTF-8 invalides ;
- segments PCRE UTF-8 invalides.

Même écart que le POSIX plus-long en locale C, sous UTF-8 :

- plus long segment BRE hybride ASCII.

Les cas de locale qui **concordent** encore avec GNU dans les trois
environnements UTF-8 comprennent le comptage / repli / préfiltre / plus-long /
sans-littéral ERE hybride ASCII, les replis Kelvin / eszett / s long, la plupart
des résumés binaires UTF-8 invalides, et `\w` PCRE ASCII. C'est pourquoi le
bench ASCII généré peut rester conditionné par la justesse alors que
`test-zpcre2-gnu` échoue encore.

### Différentiel CLI

`tests/differential.sh` contre `zgr` : **0 échec**. Couleur, FIFO, binaire /
NUL, filtres récursifs et diagnostics de pipe cassé concordent avec GNU une
fois le préfixe `grep:` réécrit en `zgr:`.

## Ce que ce bench ne mesure pas

- le POSIX gauche-le-plus-tôt/plus-long `-o` sur BRE/ERE ambigus ;
- `\<` / `\>` GNU et les limites de mot Unicode ;
- le repli de casse UTF-8 libc et `[[:alpha:]]` / `[[:upper:]]` hors ASCII ;
- la syntaxe propre à GNU que GNU accepte ou refuse (`{,2}`, `)` non échappée,
  `{32768}`) ;
- les constructions PCRE activées par accident en BRE/ERE zpcre2 (`(?=…)`,
  `\d`, `+?` paresseux) ;
- les arbres récursifs, les corpus délimités par NUL, ou les caches froids.

Utilisez `zgrc` lorsque ces sémantiques GNU sont requises. Utilisez `zgr`
lorsque le moteur zpcre2 portable est le défaut produit et que la charge reste
dans la forme du profil généré (littéraux ASCII, ERE simple, comptages et
sortie de lignes).
