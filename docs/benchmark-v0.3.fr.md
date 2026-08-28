# zgr v0.3 — benchmark comparatif

[English](benchmark-v0.3.md) | [Français](benchmark-v0.3.fr.md)

Mesure capturée le 2026-08-28 à 11:29 CEST sur Linux 6.8.0 x86_64,
avec un Intel Core i9-13900KF (32 CPU logiques), Zig 0.16.0, PCRE2 10.42,
GNU grep 3.11 et ripgrep 15.2.0. Le corpus déterministe a été généré par
`bench/generate.sh` avec 1 000 000 d'enregistrements : 93 789 827 octets et le
SHA-256
`da9fd9c2df9698ffcbeac1693c0fdf72b9357ff50fc0234c4e1d1f3f13797a3b`.

## Artefacts comparés

- zgr v0.3, tag `8076821` :
  `b72bbc31d602cc270e70ae2ea5f4326688049642c081d5642a938c6030f54dcb` ;
- zgrep v0.2, tag `1a2616d` :
  `a8b945c0aa73fce524f594a97da2e5ff83cbf5dc6459192b5ec422e17f31ee66` ;
- GNU grep 3.11 ;
- ripgrep 15.2.0, révision `e89fff89ac`.

Les deux exécutables du projet ont été compilés depuis leur tag exact avec
`zig build -Doptimize=ReleaseFast`.

## Méthode

- cache de pages chaud, `LC_ALL=C`, `taskset -c 0-15` ;
- 9 lots de 5 exécutions par outil et par charge ;
- ordre des outils permuté dans chaque lot ;
- médiane exprimée en millisecondes par exécution ;
- stdout redirigé vers un fichier ordinaire, jamais vers `/dev/null` ;
- sortie et code de retour des deux exécutables du projet et de ripgrep
  comparés à GNU grep avant de chronométrer chaque charge.

Deux vues complémentaires ont été mesurées : un passage A/B sur les 20 charges
sur fichier du profil public `generated`, puis une comparaison ciblée des
parcours v0.3 entre quatre outils.

## Résultat A/B global de v0.3

Sur les 20 cas sur fichier du profil public existant, v0.3 remporte 13 charges
et produit une accélération moyenne géométrique non pondérée de 1,039× face à
v0.2. La somme des médianes de chaque charge, avec une pondération égale, donne
une accélération similaire de 1,044× pour la suite.

| Métrique | Résultat |
|---|---:|
| charges sur fichier | 20 |
| victoires de v0.3 | 13 |
| accélération moyenne géométrique | 1,039× (3,9 %) |
| accélération de la somme des médianes à poids égal | 1,044× (4,4 %) |
| plus fort ralentissement observé sur une charge | 4,5 % |

Le résultat à l'échelle de la version confirme donc un gain global, et non une
régression générale. Les plus fortes progressions du profil public concernent
le comptage ERE à préfixe groupé, le comptage d'alternances littérales et leur
sortie.

## Médianes ciblées entre quatre outils

Les charges ciblées couvrent les changements d'alternance et de préfiltre dense
de v0.3, ainsi qu'un contrôle littéral fixe :

- contrôle littéral fixe : `rare-needle` avec sortie du nombre de lignes ;
- alternance littérale mixte :
  `rare-needle|status=500|route=/api/item/42|latency_us=999` avec sortie du
  nombre de lignes ;
- alternance à préfixe groupé : `status=(200|500)` avec sortie du nombre de
  lignes ;
- préfiltre dense à littéral requis : `status=... latency_us=` avec sortie du
  nombre de lignes ;
- alternance à préfixe groupé : `status=(500|404)` avec sortie des lignes
  numérotées.

Toutes les commandes utilisent le mode texte forcé. Les outils compatibles GNU
utilisent le mode ERE pour les charges regex ; ripgrep utilise sa syntaxe regex
par défaut.

| Charge | Mode | Lignes sélectionnées | zgr v0.3 | zgrep v0.2 | GNU grep | ripgrep | v0.3 face à v0.2 |
|---|---|---:|---:|---:|---:|---:|---:|
| contrôle littéral fixe | nombre | 1 000 | 5,829 | 5,404 | 32,174 | 12,534 | 7,9 % plus lent |
| alternance littérale mixte | nombre | 71 245 | 8,574 | 9,799 | 92,941 | 25,052 | 12,5 % plus rapide |
| alternance à préfixe groupé | nombre | 1 000 000 | 8,011 | 10,634 | 65,192 | 40,958 | 24,7 % plus rapide |
| préfiltre dense à littéral requis | nombre | 1 000 000 | 9,448 | 17,392 | 80,573 | 54,190 | 45,7 % plus rapide |
| alternance à préfixe groupé | sortie | 58 824 | 14,991 | 31,285 | 61,245 | 34,704 | 52,1 % plus rapide |

Les quatre charges qui exercent les changements de v0.3 progressent face à
v0.2, de 12,5 % à 52,1 %, et devancent GNU grep ainsi que ripgrep sur ce corpus.
Le contrôle littéral fixe oscille autour de la parité selon les captures ; son
écart de 7,9 % dans cette exécution ciblée n'est pas retenu comme conclusion de
la version.

Un contrôle exploratoire `status=[[:digit:]]{3}` a été exclu du résumé de la
version. L'inspection du matcher et un A/B de suivi montrent qu'il n'utilise
ni le moteur `AsciiClassSequence`, ni le parcours de préfiltre dense de v0.3 :
`{3}` interrompt `requiredLiteralEre`, donc il n'y a pas de préfiltre
`status=`, et l'automate de séquence de classes ne compile qu'une chaîne
d'atomes `[...]`. Le motif est un comptage PCRE2 ligne par ligne. Sur le même
corpus, il reste à parité avec v0.2 (v0.3 de 1 à 6 % plus rapide sur deux
captures de 9 exécutions). Un échantillon plus lent antérieur relève du même
bruit de quelques pourcents que le contrôle littéral fixe.

Le profil public contient déjà la vraie charge `AsciiClassSequence`,
`regexp without literal` (`[[:alnum:]_]{4}[[:space:]]+[[:alnum:]_]{7}`). Cette
charge était 4,5 % plus lente dans l'A/B archivé à 20 cas et oscille autour de
la parité à la relecture ; elle ne démontre pas une régression de
l'optimisation de préfiltre dense de v0.3.

Cet échantillon à cache chaud ne permet pas de généraliser entre machines,
systèmes de fichiers, formes de corpus ou caches froids.

Pour rejouer le même corpus déterministe et les mêmes contrôles avec le banc
public actuel, sans l'exécutable A/B archivé de v0.2 :

```sh
bench/generate.sh /tmp/zgrep-v0.3-bench.txt 1000000
BENCH_PROFILE=generated BENCH_BATCHES=9 BENCH_CPUSET=0-15 \
  BENCH_LOCALE=C ZGR=./zig-out/bin/zgr \
  bench/run.sh /tmp/zgrep-v0.3-bench.txt 5
```
