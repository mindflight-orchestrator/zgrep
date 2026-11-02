# Revue contradictoire du plan de sortie zgr 0.4.1

Analyse du 2026-11-01, confrontée au code de la v0.4.0 (`50f7533649211f87b573826784172e61c71a9830`) et à une compilation ReleaseFast indépendante. Cette revue porte sur le plan et les chemins de sortie, pas sur une optimisation déjà livrée.

Le [plan révisé](output-optimization-plan.md) intègre les corrections ci-dessous. Les [mesures et scripts de référence](baseline-output-v0.4.0-2026-11-01/README.md) sont archivés avec leurs limites.

## Verdict et preuves

Le plan initial choisissait trop tôt un tampon TTY de 16 KiB et un writer asynchrone. Plusieurs coûts et contraintes restaient mal identifiés.

La vraie v0.4.0 a été recompilée avec Zig 0.16.0 ReleaseFast. La dépendance `../zpcre2` provient du commit local `b93f4d8d999f1f000ecc3644c844294802ba78bb`, dont l'empreinte de paquet correspond exactement au verrouillage du projet.

Six scénarios de sortie fichier ont produit le même stdout et le même statut que GNU grep. Sur 1,5 million de lignes (134,17 MiB), la sortie simple de zgr prend une médiane de 71,489 ms, contre 66,135 ms avec `-a`. Ces mesures ne suffisent pas à isoler le coût de chaque phase. Le traçage compte **537 appels `writev` pour 1,5 million de lignes** : le tampon de 256 KiB regroupe déjà fortement les écritures. Les durées sous strace ne doivent pas servir à calculer un gain de performance.

La suite complète du projet n'a pas été exécutée pendant la revue. Le code du projet n'a pas été modifié.

## 1. Un flush du premier résultat ne résout pas la réactivité — risque élevé

**Vérifié :** avec stdout attaché à un PTY et une entrée qui reste ouverte, zgr 0.4.0 ne montre ni la première ni la deuxième ligne pendant les deux fenêtres de 200 ms. Elles apparaissent à EOF. Avec `--line-buffered`, chaque ligne arrive avant toute nouvelle entrée. GNU grep affiche également chacune immédiatement dans le scénario TTY par défaut.

**Angle mort :** le plan ferait apparaître la première ligne, mais pourrait laisser la deuxième attendre indéfiniment. Un tampon de 16 KiB ne garantit aucun délai.

**Correction :** définir la visibilité des résultats pendant les silences du producteur. Vider les résultats complets avant une lecture potentiellement bloquante et aux frontières de traitement bornées. Tester plusieurs résultats espacés, pas seulement le premier octet. Une garantie en octets ne constitue pas un délai temporel strict pour une regex arbitraire.

Références : `src/main.zig:212` (tampon et politique), `src/scanner.zig:3548` (flush conditionné par `line_buffered`).

## 2. Les barrières de latence précèdent parfois l'impression — risque élevé

**Vérifié dans le code :** `scanRegularBuffer` peut chercher les NUL sur tout le fichier avant toute émission. La découverte parallèle ordinaire, celle avec contexte et la capture récursive possèdent des attentes distinctes.

**Angle mort :** un writer séparé n'aide pas tant qu'aucun résultat n'est disponible. Désactiver seulement `parallelSelectedOutput` oublie les autres barrières. Désactiver tout le parallélisme peut pénaliser fortement les recherches rares.

**Correction :** cartographier les chemins fichier/stdin/contexte/récursif, leurs décisions binaires et leur première émission. Évaluer un traitement progressif par blocs ordonnés avec les mécanismes existants. Préserver les décisions qui changent les octets observables.

Références : `src/main.zig:1767`, `src/scanner.zig:3288`, `src/main.zig:710`.

## 3. La fusion de lignes peut retarder la sortie ou changer les octets — risque élevé

**Risque proposé, pas régression observée :** si l'on attend la fin d'une suite contiguë de correspondances, cette suite peut couvrir le fichier entier. De plus, une ligne qui correspond peut être supprimée pour UTF-8 invalide. La fusion fondée uniquement sur le matcher pourrait réintroduire des octets exclus.

**Correction :** borner les segments; fusionner uniquement les lignes réellement émissibles; rompre les segments aux lignes supprimées et aux frontières nécessaires. Préserver délimiteurs, dernière ligne non terminée, contexte, `-o` et `-m`. Décider l'éligibilité avant émission. Un repli après émission partielle doit reprendre au bon curseur et ne jamais rejouer les octets précédents.

Références : `src/scanner.zig:122` (suppression UTF-8), `src/scanner.zig:1842` (repli avant sortie), `src/scanner.zig:4270` (test de non-émission au repli).

## 4. L'optimisation peut intervenir après le travail gaspillé — priorité à mesurer

**Vérifié dans le code :** les chunks stockent jusqu'à 65 536 descriptions de lignes. En cas de dépassement, les résultats sont abandonnés puis le fichier est rescanné. Regrouper uniquement l'émission finale ne supprime pas ce travail.

**Correction :** mesurer découverte, allocations, repli, formatage et écriture séparément. Comparer, selon les chemins éligibles, descriptions par spans, détection de densité et chunks bornés. Ne pas simplement relever le plafond. L'essai historique avec `-m` modifie aussi le chemin d'entrée et ne constitue pas un A/B interne contrôlé.

**Complexité :** les chemins littéraux restent soumis au volume d'entrée et de sortie, soit O(N + S). On peut réduire les opérations par ligne et les passages supplémentaires. Le regroupement peut passer d'un nombre d'opérations proportionnel aux lignes émises à un nombre proportionnel aux spans, sans supprimer la lecture ni l'émission des octets.

Références : `src/scanner.zig:1666`, `src/scanner.zig:1840`, `src/scanner.zig:1932`, `src/main.zig:381`.

## 5. Le writer asynchrone est sous-spécifié — risque élevé

**Vérifié dans le code :** le récursif possède déjà des files et jusqu'à 16 MiB de sortie capturée. Les fichiers mappés sont libérés au retour du scan. Les buffers fixes utilisent parfois `WriteFailed` pour déclencher un repli interne; une erreur réelle de stdout ne doit pas être confondue avec ce cas.

**Risques :** accumulation des copies et tampons, références à une zone démappée, succès retourné avant l'échec du dernier flush, attente infinie au `join`, sortie dupliquée au repli, diagnostic d'erreur perdu. Annuler une file ne suffit pas à interrompre une écriture bloquée dans l'OS.

**Correction :** conserver l'asynchrone comme expérience conditionnelle. Définir propriétaire du writer, budget global incluant les blocs actifs, durée de vie des données, ordre, gestion des écritures partielles, propagation d'erreur, annulation et arrêt. Tester fermeture anticipée, lecteur arrêté, erreurs finales et lignes dépassant un bloc. Réutiliser les mécanismes existants lorsqu'ils répondent au besoin.

Références : `src/main.zig:823`, `src/main.zig:992`, `src/main.zig:1523`, `src/main.zig:1712`, `src/main.zig:312`.

## 6. La spécialisation comptime reste une hypothèse — risque modéré

Le code Zig est déjà compilé; la bibliothèque copie normalement dans le tampon et n'appelle le système qu'à son débordement. Le compilateur peut déjà simplifier certaines branches. Des variantes supplémentaires augmentent aussi la taille du code et peuvent dégrader les caches d'instructions.

Le chemin coloré recherche à nouveau les occurrences pour le surlignage; ce coût peut dépasser celui des conditions de formatage.

**Correction :** profiler et inspecter le code optimisé avant de spécialiser. Commencer par quelques variantes démontrées, mesurer le binaire et conserver le formatter partagé pour les combinaisons complexes. Le gain est constant, pas une amélioration générale de complexité.

Références : `src/scanner.zig:3579`, `src/scanner.zig:3817`; bibliothèque Zig 0.16, `std/Io/Writer.zig:532` et `std/Io/Threaded.zig:10732`.

## 7. Les critères de qualification peuvent favoriser les meilleurs cas — risque élevé de conclusion erronée

Les lignes toutes correspondantes favorisent la fusion. L'ancien arbre synthétique répète le même fragment 1 024 fois. Les écritures de fichiers sont mesurées à cache chaud, sans `fsync`; les PTYs ne mesurent pas un écran. Les premières mesures utilisaient des binaires 0.3.x et ne sont pas une référence 0.4.0.

**Correction :** contrôler distributions de matches et longueurs, tailles autour de 64 MiB, seuils de métadonnées et de pipeline récursif, cas colorés/numérotés, consommateurs lents et interrompus, flux sans EOF. Conserver les échantillons individuels, les identités des binaires et corpus, les statuts et les octets exacts. Mesurer temps CPU, latence des résultats successifs et mémoire, en distinguant RSS et heap. Les gains sur deux cas choisis ne suffisent pas; appliquer la matrice de non-régression à chaque changement.

Les cibles standard `test` et `test-stress` qualifient principalement `zgrc` côté différentiel/stress. Exécuter explicitement les scripts pertinents pour les deux moteurs, et inventorier les échecs expérimentaux zpcre2/GNU avant/après.

Références : `build.zig:40`, `build.zig:61`, `build.zig:69`, `tests/differential.sh:178`.

## Deuxième passe contradictoire

Seconde lecture du plan révisé, le même jour. La v0.4.0 a été recompilée en ReleaseFast dans un répertoire temporaire et testée directement. `zig-out/bin/zgr` du dépôt est en 0.3.1 et n'a pas servi. Les sondes ci-dessous utilisent des pipes et `script` (PTY); ce sont des observations comportementales, pas des distributions de latence.

### 8. `-I` sur stdin ne diffuse jamais et n'a pas de limite mémoire — risque élevé

**Vérifié :** `requiresBufferedScan` (`src/main.zig:1946`) lit tout stdin avec `allocRemaining(.unlimited)`. Avec un producteur lent, `zgr --line-buffered -I needle` (ainsi que `zgrc`) n'affiche rien avant EOF; GNU affiche chaque ligne. `yes needle | zgr -I needle | head -1` ne se termine jamais (interrompu par `timeout`); GNU se termine immédiatement.

**Angle mort :** ce chemin manquait à la cartographie et à la matrice, alors que le plan promet un `--line-buffered` qui fonctionne avec un stdin resté ouvert.

**Correction :** chemin stdin borné et diffusé pour `-I`, avec une décision binaire sur les données déjà lues et un comportement observable conforme à GNU.

### 9. Ordre stdout/stderr non spécifié — risque modéré

**Vérifié :** sur TTY, `zgr x a missing b` affiche le diagnostic `missing` après tous les résultats; GNU l'intercale entre `a` et `b`. Le contrat de réactivité ne couvrait que stdout, et la référence 0.4.0 ne comparait pas stderr.

**Correction :** sur TTY, vider stdout avant tout diagnostic. Comparer stderr normalisé et statut avec GNU.

### 10. SIGPIPE : comportement attendu absent — risque modéré

**Vérifié :** `yes needle | zgr needle | head -1` affiche `zgr: write error: Broken pipe` et sort avec 2; GNU meurt silencieusement par SIGPIPE (141). `std.Io.Threaded` de Zig 0.16 modifie la disposition de SIGPIPE (`std/Io/Threaded.zig:1661`). Le plan demandait de tester la fermeture anticipée sans fixer le résultat attendu.

**Correction :** décider explicitement (préférence : comportement GNU) et en faire un critère d'acceptation.

### 11. Flush avant une lecture « potentiellement bloquante » non implémentable tel quel — risque modéré

On ne sait pas à l'avance si une lecture bloquera. **Règle retenue :** stdout TTY et entrée non régulière ⇒ vider avant chaque lecture, soit au plus un `writev` par lecture de 256 KiB. Pour `-z`, GNU 3.11 retarde lui aussi des enregistrements terminés par NUL jusqu'à EOF dans la sonde : le plan doit choisir entre suivre GNU et être plus strict, puis l'écrire.

### 12. Protocole statistique trop faible et cibles non déclarées — risque élevé de conclusion erronée

**Vérifié dans `file-results.json` :** dispersion min–max de 15 à 20 % sur 7 runs, 158 % pour `zgrc -a`. Une comparaison de médianes sur 2×9 runs ne détecte pas fiablement 5 %; sur le cas sparse (10 ms), 5 % ≈ 0,5 ms, soit le bruit de lancement. Le plan exigeait 10 % sur des « cibles déclarées » qu'il ne nommait pas, ce qui ouvre la porte à une sélection a posteriori.

Le i9-13900KF est hybride (cœurs P et E) et l'affinité n'était pas fixée : distributions potentiellement bimodales. Les seuils parallèles sont de fait réglés pour 32 threads. Une seule machine a été mesurée.

**Correction :** cibles figées avant implémentation; paires alternées, intervalle de confiance par bootstrap ou test de rangs, beaucoup plus de runs pour les cas courts, compteurs d'instructions en métrique secondaire; mesures aussi sur 4 cœurs (`taskset`); vérification de version et d'empreinte des binaires par le script de mesure.

### 13. Priorités : le cas le plus proche de sa borne était visé en premier — risque modéré

« all plain » (71,5 ms) est déjà proche de `-a` (66,1 ms) et de `cat` historique (≈ 47 ms). Les écarts mesurés les plus nets sont ailleurs : `zgrc` dense plain est **plus lent que GNU** (104,6 contre 101,3 ms); le CPU médian (user + système) de zgr dépasse celui de GNU de 1,6× (132 contre 84 ms en all plain, 166 contre 101 en dense plain); colorisé 145 ms; numérotation +22 ms; le préscan NUL représente ≈ 7,5 % (delta `-a`). Le RSS de 154 Mo contre 18 Mo (mapping compris) pèse avec `xargs -P`.

Les spans sur entrée mappée peuvent aller directement à `writev` sans copie; le plan doit trancher. En zéro copie, une troncature de l'entrée pendant le scan (rotation de logs) produit `EFAULT` à l'écriture plutôt qu'un `SIGBUS`.

Cas absents de la matrice : entrée identique à la sortie (`zgr x f >> f`), stdout fermé, `/dev/full`, fichier qui grossit pendant la lecture, cache froid.

### 14. Le correctif visible était bloqué par la qualification des performances — risque de livraison

Le défaut ressenti par l'utilisateur est un bug de compatibilité (`tail -f log | zgr ERROR` muet sur terminal), pas un problème de débit. L'enfermer dans la matrice complète des optimisations retarde sa livraison pour un gain de quelques millisecondes sur environ 70 ms. Aucun critère d'abandon ne bornait l'effort.

**Correction :** séparer 0.4.1 (réactivité et compatibilité : §8 à §11, corrigés par §15 à §18) et 0.4.2 (optimisations), limiter dans le temps chaque optimisation.

## Troisième passe, 2026-11-02

Sondes sur la v0.4.0 recompilée (empreintes identiques à la référence), comparée à GNU grep 3.11. Elles corrigent des affirmations des passes précédentes.

### 15. L'ordre stdout/stderr hors TTY reposait sur une prémisse fausse

**Vérifié :** vers un fichier ou un pipe (`> o 2>&1`), GNU intercale aussi résultats et diagnostics. Le §9 limitait le correctif au TTY. Il doit s'appliquer à toutes les sorties.

### 16. `-z --line-buffered` n'est pas retardé par GNU

**Vérifié :** GNU 3.11 et zgr 0.4.0 émettent chaque enregistrement immédiatement, sur PTY comme sur pipe. Le §11 confondait ce cas avec `-z` seul, retardé sur TTY par les deux outils.

### 17. Diagnostics perdus et cas `-I` manquants

**Vérifié :** stderr n'était vidé qu'en fin d'exécution, si bien que `zgr needle absent gros | head -1` perdait l'erreur sur `absent`. Le blocage de `-I` touche aussi les FIFO et `/dev/stdin`. Un SIGPIPE ignoré par le parent doit conserver le diagnostic et le statut 2.

### 18. Frontières binaires et NUL tardif

**Vérifié :** les résultats de GNU 3.11 suivent des blocs de 96 KiB, contre 256 KiB pour zgr. Avec un NUL à 100 KiB, zgr affiche 0 ligne et GNU 14 043. Sur stdin, zgr s'arrêtait en silence à un NUL tardif là où GNU signale `binary file matches`.

### 19. Le critère TTY se contredisait

Écarter du défaut un flush TTY jugé trop coûteux revenait à écarter le correctif. La barre devient : hors TTY, pas de régression; sur TTY, pas plus lent que GNU.

### 20. Cibles 0.4.2 dans le bruit et périmètre 0.4.1 trop large

**Vérifié dans `file-results.json` :** `zgrc` dense contre GNU (IC 95 % de −2,3 à +17,7 %) et le préscan NUL en temps réel (de −4 à +16,3 %) ne se distinguent pas du bruit. Le préscan plafonne de toute façon sous le seuil de 10 %, mais il pèse sur le CPU (132 contre 96 ms). Le premier résultat sur PTY arrive en 11–13 ms pour 134 Mio et 52 ms pour 2 000 fichiers : ces barrières passent à la 0.4.2.

## Ordre de livraison recommandé et adopté

1. Référence 0.4.0 reproductible, état des tests (stdout, stderr, statuts) et profil des coûts.
2. **0.4.1 :** contrat de réactivité, `-I` sur stdin, ordre stdout/stderr, décision SIGPIPE; gates de justesse et de non-régression.
3. **0.4.2 :** cibles déclarées à l'avance, puis optimisations locales (spans, travail de découverte abandonné) une à une, limitées dans le temps.
4. Spécialisation uniquement démontrée par les mesures.
5. File asynchrone facultative, soumise aux mêmes gates de justesse, ressources et performance.

Le tampon TTY fixé arbitrairement à 16 KiB du premier plan et le flush limité au premier résultat sont retirés. Les contraintes d'éligibilité, de repli, de durée de vie et d'arrêt sont explicites. Les mesures 0.4.0 complètent les historiques sans les réétiqueter. Aucun bump de version ni changement fonctionnel n'est effectué par cette sauvegarde.
