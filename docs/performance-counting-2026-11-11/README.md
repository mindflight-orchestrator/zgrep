# Comptage adaptatif : preuves de l'optimisation retenue

[Rapport et comparaison lisible](../performance-audit.fr.md#optimisation-retenue--comptage-adaptatif)

Ce dossier décrit le second essai, fondé sur la recherche directe des lignes
correspondantes. Le correctif est intégré aux sources du dépôt. Les captures
décrivent l'état mesuré avant commit. Il remplace la première expérience
écartée de l'audit précédent.

| Fichier | Contenu |
|---|---|
| `metadata.json`, `candidate2-inputs.json`, `retained-change.patch` | État retenu, sources, empreintes, commandes via les scripts et patch applicatif |
| `baseline.json` | Référence préservée avant ce changement ; moteur de `0201712`, outils de mesure du premier audit |
| `final-auto.json`, `final-text.json` | 25 tours appariés, programmes complets, options identiques entre outils |
| `final-four-core.json` | 15 tours avec affinité 2,4,6,8 ; même fichier partagé entre les workers de zgr |
| `final-micro.json` | 25 tours sur les douze fonctions internes, corpus déjà en mémoire |
| `dense-confirmation.json`, `confirm-dense.py` | Contrôle dense dédié à 51 tours pour départager les médianes instables de la série complète |
| `final-*.log`, `dense-confirmation.log` | Sorties lisibles des mesures ci-dessus et des distributions |
| `final-sparse-then-dense.json`, `final-dense-then-sparse.json` | Changement de densité dans les deux sens |
| `final-one-in-eight.json`, `final-rejected-words.json` | Densité intermédiaire et occurrences rejetées par les frontières de mots |
| `final-long-lines.json`, `final-empty-then-rejected.json` | Lignes longues, puis préfixe sans résultat suivi de mots rejetés |
| `corpora.json`, `generate-all-distributions.py` | Tailles et empreintes des six distributions ; génération déterministe vérifiée par rejeu |
| `compare-count.py`, `final-measurements.py` | Comparateur paramétrable et recette locale exécutant les séries successivement |
| `qualification-final.log`, `qualification-safe.log`, `qualify-final.py` | 86 tests ReleaseFast, 43 tests ReleaseSafe, différentiels et 3 072 contrôles de fuzzing |
| `check-records.py`, `records.json`, `qualification-records.log` | 44 contrôles GNU sur gros fichiers newline/NUL, deux moteurs, quatre CPU |
| `summary.json` | Médianes et réductions de temps calculées à partir des rapports appariés |
| `experiments/` | Premier candidat, diagnostic du repli après des mots rejetés et mesures exclues de la qualification finale |

Les preuves finales totalisent **6 248 vérifications** de résultat ou sortie
pendant les benchmarks, auxquelles s'ajoutent les 44 contrôles de gros fichiers.
Les binaires qualifiés sont identiques octet pour octet aux binaires mesurés.
Les variations secondaires défavorables d'environ 1,1 à 2,4 % sont détaillées
dans le rapport ; elles ne sont pas cachées par les gains sur les cas rares.

## Reproduire

Utiliser Zig 0.16.0, les dépendances verrouillées, ReleaseFast et LLVM. Construire
la référence depuis les sources applicatives de `0201712`, dans une copie
isolée ; conserver séparément le candidat et la référence. Pour les mesures
internes avant/après, installer les outils `bench/internal.*` et l'étape
`bench-internal` des deux côtés, puis appliquer le patch uniquement au candidat.
Les empreintes de `baseline.json` et `metadata.json` identifient les artefacts
réellement mesurés. Les chemins absolus des captures décrivent la machine locale.

Depuis la racine du dépôt, avec les chemins de binaires adaptés :

```sh
python3 docs/performance-counting-2026-11-11/compare-count.py \
  --baseline /tmp/baseline/bin/zgr --candidate /tmp/candidate/bin/zgr \
  --corpus /tmp/zgrep-audit.txt --suite full --cpu 2 --repeats 25 \
  --output /tmp/comptage-auto.json
```

Ajouter `--input-mode text` pour passer `-a` à tous les outils. `--cpu 2,4,6,8`
contrôle l'affinité ; choisir des CPU autorisés sur la machine. Les résultats
JSON doivent avoir de nouveaux noms. Le comparateur importe le module maintenu
`bench/compare.py` et en enregistre l'empreinte.

Le générateur de distributions écrit à côté de son propre fichier : le copier
dans un nouveau dossier temporaire avant de l'exécuter. `check-records.py`,
`qualify-final.py` et `final-measurements.py` décrivent la disposition locale
`baseline/`, `candidate2/`, `qualified/`, `corpora/` ; adapter ces chemins pour
un rejeu. Ne pas lancer de compilation ou de tests en parallèle des mesures.

## Expériences non retenues

Le premier candidat reparcourait le préfixe déjà écarté après beaucoup de
candidats rejetés par `-w` : environ 17 % de temps supplémentaire selon le ratio
apparié du cas `empty-then-rejected`. Le second candidat reprend au début de
la ligne courante ; ce ralentissement disparaît dans les mesures finales.

`candidate1-focused.json` échoue sur la présentation du zéro par ripgrep dans
le cas inversé dense : `--include-zero` manquait au lanceur expérimental.
Le lanceur corrigé l'applique aux comptages. Ce n'était pas une divergence du
moteur zgr. Le script initial est conservé pour expliquer cette capture.

`candidate1-full.json` et `candidate1-micro.json` ont fini avec tous leurs
contrôles de résultat réussis, mais leurs mesures se sont partiellement
chevauchées. `overlap-note.json` les exclut explicitement de la preuve de
performance finale. Les séries finales ont été exécutées successivement.
