# Preuves de l'audit des chemins lents — 11 novembre 2026

[Rapport](../performance-audit.fr.md)

Ce dossier conserve la première campagne. L'optimisation suivante et ses
preuves se trouvent dans [le dossier du comptage adaptatif](../performance-counting-2026-11-11/README.md).
Les mentions de moteur actif ou inchangé ci-dessous décrivent l'état à la fin
de cette première campagne, avant le nouveau correctif.

Le prototype de comptage **n'est pas appliqué au moteur actif** : le gain sur
les cas rares s'accompagne d'une régression dense dans la série complète.
Les fichiers nommés `final` désignent le dernier prototype étudié, conservé
sous forme de patch ; `retained` désigne le moteur inchangé avec les outils
maintenus dans ce lot.

| Fichier | Contenu |
|---|---|
| `metadata.json` | Sources du prototype final, SHA-256, compilateur, hôte, commandes et limite de `perf` |
| `literal-count-prototype.patch` | Prototype non intégré et son test différentiel ; applicable à la référence |
| `baseline.json` | Référence source et exécutables préservés avant modification |
| `baseline-kernels.zig`, `micro-build-command.json`, `micro-build.log` | Adaptateur et compilation de la bibliothèque de référence |
| `micro-final.json`, `micro-final.log` | Prototype final : 25 tours appariés sur douze vraies fonctions Zig, 648 vérifications |
| `paired-application.py`, `application-final.json`, `application-final.log` | Prototype final face à la référence et ripgrep/GNU, options équivalentes, 1 615 vérifications |
| `dense-check.py`, `dense-check.json`, `dense-check.log` | Contrôle isolé du comptage dense avant la série complète ; cette dernière retrouve la régression |
| `final-validation.log`, `safe-validation.log` | Tests unitaires, différentiels, fuzzing et compilation du prototype final |
| `retained-metadata.json`, `retained-build.log` | Sources et binaires du moteur actif inchangé, outils recompilés, vérification du rejeu du patch |
| `retained-internal-smoke.json` | Microbenchmarks maintenus avec le moteur actif : 60 vérifications |
| `comparator-auto-smoke.json`, `comparator-text-smoke.json` | Comparateur maintenu avec le moteur actif : 260 vérifications dans chacun des deux modes |
| `experiments/` | Essais antérieurs : spécialisation sans sélection par densité, confirmation dont quatre cœurs, alignement non retenu |

Les chemins absolus des scripts et JSON décrivent l'expérience locale ; les
binaires et corpus volumineux ne sont pas archivés. Les scripts conservés ici
sont des recettes d'expérience à adapter dans un dossier temporaire. Le
comparateur maintenu est [bench/compare.py](../../bench/compare.py), et les
microbenchmarks sont [bench/internal.py](../../bench/internal.py) et
[bench/internal.zig](../../bench/internal.zig).

La bibliothèque de référence a été compilée avant modification, à partir des
sources applicatives de `0201712`, avec l'adaptateur `baseline-kernels.zig`
(nommé `micro.zig` dans la commande originale). Pour la reconstruire, utiliser
ce commit dans une copie isolée, son zpcre2 verrouillé, cet adaptateur et la
commande enregistrée en adaptant les chemins. Les fonctions exportées ont le
même contrat que le nouvel adaptateur maintenu.

Pour reconstruire le prototype final, utiliser les outils de ce lot et
appliquer `literal-count-prototype.patch` dans une copie isolée de la référence.
Le rejeu a été vérifié : il restitue exactement l'empreinte de `src/scanner.zig`
enregistrée dans `metadata.json`. Les résultats de `experiments/` concernent
des versions intermédiaires et ne qualifient pas ce patch final.

Les données anciennes de `../benchmark-backends-2026-11-11/` restent intactes.
Leur mode binaire différait entre outils ; les séries de cet audit distinguent
explicitement les modes `auto` et `text`. Les vérifications `smoke` portent
sur le corpus de 100 000 lignes et ne remplacent pas les mesures appariées
sur un million de lignes.
