# Archives des tests et benchmarks

[Documentation actuelle](../README.md) · [Latest report in English](../benchmark-backends.md)

Ce dossier regroupe les rapports et expériences antérieurs à la recherche du
11 novembre 2026. Les fichiers déplacés conservent leur contenu et leur
organisation relative : mesures, versions, empreintes, résultats de tests et
scripts d'origine restent consultables.

Ces captures décrivent les binaires et les conditions de leur époque. Les noms
des exécutables, les défauts observés et les commandes peuvent avoir changé.
Les scripts d'expérience conservent notamment leurs chemins temporaires
d'origine ; les lanceurs maintenus sont dans [`../../bench/`](../../bench/) et
les tests actifs dans [`../../tests/`](../../tests/).

## Comparaisons d'août 2026

| Sujet | Rapport |
|---|---|
| Benchmark v0.2 | [Français](benchmark-v0.2.fr.md) · [English](benchmark-v0.2.md) |
| Benchmark v0.3 | [Français](benchmark-v0.3.fr.md) · [English](benchmark-v0.3.md) |
| Moteur zpcre2 v0.4 | [Rapport](benchmark-zpcre2-v0.4.md) |
| zgr et zgrc | [Français](benchmark-zgr-zgrc.fr.md) · [English](benchmark-zgr-zgrc.md) |
| ripgrep fourni par Cursor | [Français](cursor-grep-comparison.fr.md) · [English](cursor-grep-comparison.md) |
| Suite officielle GNU grep 3.12 | [Français](gnu-grep-3.12-compatibility.fr.md) · [English](gnu-grep-3.12-compatibility.md) |
| Analyse des chemins des moteurs avec les anciens noms | [Note](grep-comparison/analysis.md) |

## Réactivité et sorties, novembre 2026

| Sujet | Rapport et pièces associées |
|---|---|
| Premières observations sur les binaires installés 0.3.x | [Référence du 1er novembre](baseline-output-2026-11-01/README.md) |
| Référence v0.4.0 recompilée | [Mesures, scripts et provenance](baseline-output-v0.4.0-2026-11-01/README.md) |
| Plan 0.4.1 / 0.4.2 | [Plan d'optimisation](output-optimization-plan.md) |
| Revue du plan et corrections | [Revue contradictoire](output-optimization-review-2026-11-01.md) |
| Qualification de la 0.4.1 | [Résultats du 2 novembre](qualification-0.4.1-2026-11-02/README.md) |

Le rangement du plan 0.4.1 / 0.4.2 ne signifie pas que ses propositions 0.4.2
ont été réalisées ou abandonnées. Leur qualification reste distincte des
correctifs 0.4.1 et de la comparaison LLVM du 11 novembre.

The files above are historical evidence preserved without content changes.
Use the current documentation and maintained runners for new measurements.
