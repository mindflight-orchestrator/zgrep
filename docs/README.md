# Documentation

Le point de départ actuel est **[l'audit des chemins plus lents que
ripgrep](performance-audit.fr.md)**. Il complète la [recherche sur les backends
Zig et la comparaison LLVM / Rust / C](benchmark-backends.fr.md) du 11 novembre
2026 avec des microbenchmarks et une optimisation du comptage adaptatif retenue
localement. Le premier prototype écarté reste documenté dans l'historique.

| À lire | Contenu |
|---|---|
| [Audit de performance](performance-audit.fr.md) | Temps totaux Zig/Rust/C, comptage adaptatif, gains et compromis |
| [Preuves du comptage adaptatif](performance-counting-2026-11-11/README.md) | Mesures finales sur un/quatre CPU, distributions, empreintes et validation |
| [Synthèse en français](benchmark-backends.fr.md) | Zig 0.16/0.17, LLVM et backend natif, comparaison avec ripgrep et GNU grep |
| [English report](benchmark-backends.md) | English version of the current research and comparison |
| [Données et preuves](benchmark-backends-2026-11-11/README.md) | Mesures individuelles, versions, empreintes, assembleur et validation locale |
| [Archives](archive/README.md) | Anciens rapports, résultats de tests, plans et scripts d'expérience |

Les scripts maintenus restent dans [`../bench/`](../bench/) :
`compare.py` réalise la comparaison LLVM / Rust / C, tandis que les lanceurs
shell couvrent les fichiers, les arbres, les enregistrements NUL et le ripgrep
de Cursor. Les suites de [`../tests/`](../tests/) restent utilisées par les
étapes de test de [`build.zig`](../build.zig) et la CI.

Les archives conservent les observations de leur date d'origine. Elles
n'établissent pas l'état actuel du projet. Le plan d'optimisation 0.4.2 y reste
consultable avec ses propositions encore non qualifiées.
