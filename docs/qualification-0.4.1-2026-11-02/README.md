# Qualification 0.4.1 — réactivité et compatibilité (2026-11-02)

[Plan](../output-optimization-plan.md) · [Revue contradictoire, §15 à §20](../output-optimization-review-2026-11-01.md) · [Référence v0.4.0](../baseline-output-v0.4.0-2026-11-01/README.md)

Référence de comportement : **GNU grep 3.11** (`/usr/bin/grep`). Machine : i9-13900KF, gouverneur `powersave`, Zig 0.16.0, `LC_ALL=C`. Les binaires de référence ont été recompilés depuis `v0.4.0` hors du dépôt et leurs SHA-256 correspondent à `provenance.json` (zgr `706eae7c…`, zgrc `a84e1579…`).

## État

Le correctif 0.4.1 est implémenté et commité. La **qualification n'est pas terminée** : la série restreinte à 4 cœurs et la mesure de latence PTY n'étaient pas finies au moment de la sauvegarde, et un cas `zgrc` reste à trancher (voir « Performance »).

## Corrections de comportement (zgr et zgrc)

| Sujet | v0.4.0 | 0.4.1 |
|---|---|---|
| Terminal, entrée non régulière | résultats visibles seulement à EOF | vidés avant chaque lecture (`scanner.InputReader`) |
| `-I` sur stdin, FIFO, `/dev/stdin` | lit tout en mémoire, ne se termine jamais sur `yes \| … \| head -1` | flux borné, arrêt au premier tampon contenant un NUL |
| Ordre stdout/stderr | diagnostics après tous les résultats, même vers un fichier | stdout vidé avant chaque diagnostic, stderr vidé après |
| SIGPIPE | `write error: Broken pipe`, statut 2 | silencieux, statut 141 ; diagnostic conservé si le parent ignore SIGPIPE |
| stdout fermé | `NotOpenForWriting` | `write error: Bad file descriptor`, statut 2 |
| Frontière binaire | 256 KiB | 96 KiB, comme GNU 3.11 |
| NUL tardif sur stdin | arrêt silencieux | `binary file matches` |
| stderr fermé | pouvait interrompre la recherche | sans effet sur les résultats |

Écarts assumés : `-z` sur terminal affiche chaque enregistrement immédiatement (GNU le retient jusqu'à EOF) ; avec `-I`, zgr cesse de lire au NUL alors que GNU draine son entrée (octets identiques, le producteur voit le pipe se fermer plus tôt) ; sur un pipe, la classification binaire dépend du rythme des écritures du producteur, pour GNU comme pour zgr.

## Tests

- `tests/streaming.py` (nouveau, branché dans `zig build test` et `test-zpcre2-gnu`) : **127 écarts avec GNU sur la v0.4.0** ([liste](streaming-failures-v0.4.0.txt)), **0 sur la 0.4.1**, pour `zgr` et `zgrc`, en ReleaseFast et ReleaseSafe. Il couvre 22 scénarios lents sur PTY et pipe, l'ordre des diagnostics, SIGPIPE, FIFO, stdout fermé ou plein et 7 positions de NUL × 10 options × fichier ou stdin.
- Passent : `zig build test`, `test-zpcre2`, `test-fuzz`, `test-stress`, `tests/differential.sh` sur `zgr`.
- Échecs **déjà présents sur la v0.4.0** et inchangés : `tests/regex-semantics.sh` (« BRE grouping and alternation ») et `tests/locale-semantics.sh` (« C.utf8 / fixed accented case folding ") sur `zgr`. Ces scripts s'arrêtent au premier échec, donc l'inventaire complet reste à faire. `test-zpcre2-gnu` n'a pas été relancé en entier après les changements.

## Performance

Méthode : paires alternées aléatoirement (`benchmark-paired-original.py`), corpus de 1,5 M de lignes (SHA-256 `77d7d8cf…`), sortie vers un fichier, bootstrap de la médiane des rapports appariés, octets de sortie comparés à chaque paire. Une machine, un gouverneur, cache chaud, sans `fsync`.

**Première série (avant correctif d'alignement)** — [résultats](paired-before-alignment.txt) : `zgr` sortie dense **+12,4 %** (IC +9,9 à +14,8), reproduit à +11 % puis +11,7 % sur 4 cœurs ; `zgr` stdin regex +3,4 %, pipe regex +5,6 %.

**Cause** : une sensibilité à la disposition du code. Isolés, le champ d'option seul (−1,2 %) et le bloc de 96 KiB seul (−1,5 %) ne régressent pas ; la version candidate complète, ni le `main.zig` ni la gestion SIGPIPE seule, ne l'expliquent. Du remplissage inerte de 16 à 512 octets dans `scanReader` fait varier le même chemin de −2,6 % à +2,5 %. Alignement de 64 octets forcé sur `scanLiteralFast`, `selectedOutputWorker`, `findParallelOutputMatch`, `emitLine` et `emitDecoratedLine` : de −2,1 % à +2,4 % sur cinq décalages (contre +10,6 % sans). La cause microarchitecturale exacte n'a pas été établie (`perf stat` est interdit : `perf_event_paranoid=4`).

**Série après alignement, sans restriction** — [résultats](paired-after-alignment-unrestricted.txt) :
- `zgr` : aucun écart hors bruit sauf `stdin -I`, **−27 %** (IC −28,9 à −24,7).
- `zgrc` : `stdin -I` −21 % ; `dense plain` −7,9 % (effet de disposition, pas un gain) ; **`pipe` +8,9 % (IC +1,7 à +11,3), au-dessus du seuil de 5 % du plan, à confirmer** ; `forced text` +2 %, `colored` +3,2 % (IC proches de zéro).

**Série restreinte à 4 cœurs (`taskset -c 0,2,4,6`)** — [résultats partiels](paired-after-alignment-taskset-PARTIAL.txt), 16 charges sur 24 : `zgr` toutes dans le bruit à l'exception de `stdin -I` (−23 %) ; `zgrc dense plain` −11,1 %, `zgrc numbered` +2,1 % (IC +1,4 à +5,1).

À faire avant de déclarer la 0.4.1 qualifiée : terminer cette série, rejouer `zgrc pipe` en lot indépendant, mesurer la latence du premier résultat sur PTY (`probe-pty-original.py`) face à GNU, et relever la taille du binaire (831 688 → 833 896 octets).

## Limites

Les sondes PTY utilisent `OPOST` désactivé et mesurent la disponibilité des octets, pas un affichage réel. Les timings de fichier incluent le lancement et des écritures en cache. Les scripts `*-original.py` codent en dur les chemins du répertoire de travail de la session ; ils servent de recette, pas d'outil prêt à l'emploi. Les binaires de référence ne sont pas archivés : reconstruire depuis le tag `v0.4.0` et vérifier les SHA-256 ci-dessus.
