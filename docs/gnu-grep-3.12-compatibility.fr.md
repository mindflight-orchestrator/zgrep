# Comparaison avec la suite officielle de GNU grep 3.12

[English](gnu-grep-3.12-compatibility.md) | [Français](gnu-grep-3.12-compatibility.fr.md)

Cette comparaison a été enregistrée le 28 août 2026 depuis le commit
`0e97e41`, sous Linux 6.8.0-138 x86_64 avec Zig 0.16.0. Elle complète les tests
différentiels ciblés du dépôt en exécutant sans modification la propre suite
fonctionnelle de GNU grep contre les deux moteurs d'expressions régulières de
zgr.

## Reproductibilité

- source officielle : [GNU grep 3.12](https://ftp.gnu.org/gnu/grep/grep-3.12.tar.xz) ;
- SHA-256 de la source :
  `2649b27c0e90e632eadcd757be06c6e9a4f48d941de51e7c0f83ff76408a07b9` ;
- configuration : `configure --disable-nls` ;
- compilation : `make -j8` ;
- suite fonctionnelle : le `tests/Makefile` généré, lancé avec
  `make -j8 check` après `make clean`.

Le binaire GNU natif a d'abord servi de référence. Pour chaque exécution de
zgr, seul le point d'entrée généré `src/grep` a été remplacé par un lanceur du
binaire candidat figé. Les lanceurs `egrep` et `fgrep` générés par GNU ont donc
utilisé le même candidat via `grep -E` et `grep -F`. Aucun fichier ni aucune
commande de test n'a été modifié.

Binaires ReleaseFast testés :

- `zgr` (PCRE2 C) :
  `fdc9ecb6223ca8fdab9ccd807f1a6b70cc5e8f6e53cdbcb4e82670126133aa92` ;
- `zgr-zpcre2` :
  `113499f16a8137c0053763978d082ecc76987cc2aca2b61dfb6a403be9585358`.

Les campagnes candidates complètes désactivaient les fichiers core et
limitaient chaque fichier généré à 128 Mio. Cette borne a été ajoutée après
qu'une première exécution non bornée a révélé l'échec `in-eq-out-infloop`
décrit ci-dessous ; elle ne modifie pas les commandes de test officielles.

## Résultats

| Implémentation | Total | Réussites | Ignorés | XFAIL | Échecs | XPASS | Erreurs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| GNU grep 3.12 | 128 | 107 | 19 | 2 | 0 | 0 | 0 |
| zgr, PCRE2 C | 128 | 84 | 19 | 0 | 23 | 2 | 0 |
| zgr-zpcre2 | 128 | 80 | 19 | 1 | 27 | 1 | 0 |

Les deux XPASS du moteur C, `glibc-infloop` et `triple-backref`, sont des
réussites inattendues positives sur des cas que GNU marque comme échecs
attendus. Le moteur zpcre2 réussit `triple-backref` ; `glibc-infloop` reste
XFAIL.

Le `make check` GNU complet exécute aussi les tests de gnulib. Cinq tests de
sockets ont échoué avec `EBADF` dans le bac à sable. Ils sont hors de la suite
fonctionnelle de 128 tests de grep et ne sont attribués à aucune implémentation
de grep.

## Comparaison des échecs

Les deux moteurs échouent sur ces 22 fichiers de test :

`binary-file-matches`, `bre`, `color-colors`, `context-0`, `ere`,
`filename-lineno`, `hangul-syllable`, `help-version`, `in-eq-out-infloop`,
`include-exclude`, `initial-tab`, `max-count-overread`, `pcre`, `pcre-abort`,
`pcre-context`, `pcre-wx-backref`, `skip-read`, `stack-overflow`,
`version-pcre`, `warn-char-classes`, `write-error-msg` et `yesno`.

Seul le binaire PCRE2 C échoue sur `pcre-utf8-bug224`.

Seul le binaire zpcre2 échoue sur `backref`, `c-locale`,
`case-fold-char-type`, `spencer1` et `spencer1-locale`. Il réussit
`pcre-utf8-bug224` et davantage de cas BRE individuels que le moteur C, mais
il régresse sur les références arrière entre motifs, le comportement en locale
C, le repli de casse dépendant de la locale et plusieurs expressions de la
suite Spencer. Le bilan est de quatre fichiers de test réussis en moins.

## Constats prioritaires

1. `in-eq-out-infloop` : zgr ne refuse pas un fichier utilisé simultanément
   comme entrée et comme sortie redirigée. Il peut le faire grossir jusqu'à
   épuisement du stockage ; GNU grep renvoie le statut 2.
2. `stack-overflow` : plusieurs cas officiels terminent zgr par une erreur de
   segmentation au lieu de signaler proprement un dépassement de pile.
3. `max-count-overread` et certaines parties de `yesno` : zgr consomme stdin
   au-delà de la limite de correspondances `-m`, ce qui modifie le flux restant
   pour l'appelant.
4. `include-exclude`, `context-0` et `yesno` : les filtres récursifs, les
   séparateurs de contexte et les options de regroupement diffèrent visiblement
   de GNU grep.
5. zpcre2 ajoute des régressions de locale, de repli de casse et de la suite
   Spencer aux échecs communs.

## Interprétation

Un microbenchmark du moteur regex et une suite complète de compatibilité grep
ne mesurent pas la même chose. Le premier peut montrer zpcre2 plus rapide que
PCRE2 C sur une expression isolée. La seconde teste aussi l'analyse des
options, les entrées-sorties par flux et mmap, le découpage en lignes, le
formatage, la récursion, les locales, les diagnostics et la sémantique GNU
exacte. La vitesse du moteur ne garantit donc ni une latence globale plus
faible ni une meilleure compatibilité CLI.
