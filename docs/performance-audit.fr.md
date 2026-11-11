# Audit des chemins plus lents que ripgrep — 11 novembre 2026

[Index](README.md) · [Données et scripts](performance-audit-2026-11-11/README.md)

## Optimisation retenue : comptage adaptatif

**Le second essai est intégré aux sources du dépôt.** Sur les comptages
absents, rares, de mots entiers et sans distinction de casse, il réduit le
**temps total de 12 à 15 % sur un cœur**, et de **8 à 11 % sur quatre cœurs**
(rapports appariés). Les contrôles de résultat passent. Quelques cas secondaires
régressent de **1,1 à 2,4 %** ; le compromis est détaillé ci-dessous. Les
captures décrivent l'état mesuré avant commit ; leurs empreintes identifient
les sources et les binaires qualifiés.

### Temps total après optimisation, face à Rust et C

Même corpus de **93,8 Mo et un million de lignes**, chaud, locale C,
Zig 0.16.0 **ReleaseFast avec LLVM**. Un CPU logique, mode `auto` sans `-a`
pour tous, 25 tours après deux échauffements. Ces médianes en **millisecondes**
incluent le lancement et la sortie vers un fichier. Référence et candidat
sont exécutés alternativement dans la même série : les anciens temps de
15,6 ms plus bas ne servent pas à calculer ce nouveau gain.

| Opération | zgr avant | zgr optimisé | ripgrep — Rust | GNU grep — C |
|---|---:|---:|---:|---:|
| Littéral absent (`-F -c`) | 11,11 | 9,39 | 9,82 | 23,19 |
| Littéral rare (`-F -c`) | 11,05 | 9,54 | 9,95 | 30,78 |
| Mot entier (`-F -w -c`) | 11,16 | 9,62 | 9,97 | 32,18 |
| Sans distinction de casse (`-F -i -c`) | 11,81 | 10,06 | 13,40 | 31,94 |
| Sortie rare numérotée (`-F -n`) | 14,46 | 14,47 | 12,00 | 37,81 |
| Littéral dense (`-F -c`), contrôle dédié¹ | 13,13 | 13,13 | 28,25 | 27,37 |

¹ Le contrôle dense dédié utilise **51 tours**, exécutés séparément :
13,1255 ms avant et 13,1257 ms après ; ratio apparié 0,999, intervalle à 95 %
[0,990 ; 1,003]. La série complète avait des médianes brutes de 11,80 et
12,85 ms mais un ratio apparié de 1,002 [0,975 ; 1,007]. La fréquence de la
machine varie et le rapport des médianes ne résume pas les mêmes écarts que
les comparaisons tour par tour. Le contrôle dédié ne montre ni gain ni
régression établis du comptage dense sur ce corpus.

Sur les comptages rares et absents, `zgr` passe légèrement devant ripgrep dans
cette série ; cela ne constitue pas un classement universel. Sur quatre CPU,
le comptage rare passe de **4,23 à 3,83 ms**, face à **8,74 ms** pour ripgrep.
Notre découpage du fichier en workers contribue à ce résultat ; il ne prouve
pas une supériorité générale du langage Zig sur Rust.

**`-F -n` n'est pas accéléré par ce correctif.** Avec `-a` pour tous, la sortie
rare numérotée donne 10,61 ms avant, 10,62 ms après et 12,01 ms pour ripgrep.
La détection binaire et la numérotation n'ont pas été modifiées.

[Données complètes](performance-counting-2026-11-11/README.md) ·
[Série auto](performance-counting-2026-11-11/final-auto.json) ·
[Série texte](performance-counting-2026-11-11/final-text.json) ·
[Quatre CPU](performance-counting-2026-11-11/final-four-core.json) ·
[Contrôle dense](performance-counting-2026-11-11/dense-confirmation.json).

### Ce qui change dans le moteur

La lecture du [chemin rapide de ripgrep 15.2.0](https://github.com/BurntSushi/ripgrep/blob/15.2.0/crates/searcher/src/searcher/core.rs)
a orienté l'essai : chercher la prochaine correspondance, compter sa ligne
une seule fois, puis reprendre après cette ligne. Notre chemin de sortie
possédait déjà une stratégie similaire ; le comptage du CLI utilisait une
boucle traitant tous les séparateurs.

`countLiteralSelected` (`src/scanner.zig:2160`) choisit désormais
`countLiteralSparse` (`:2174`) pour les comptages non inversés, sans ancrage de
ligne, sur au moins 4 Kio, avec un motif de 1 à 32 octets sans séparateur.
Le nouveau chemin utilise le véritable `Literal.find` et les vérifications
de mots existantes. Il ne compte pas le total des lignes non sélectionnées.

Toutes les 32 occurrences candidates, acceptées ou rejetées, il vérifie la
progression. Si elle est inférieure à 8 Kio, il reprend le comptage régulier
sur la suite du fichier. Cette décision peut être prise après une région
initiale peu dense ; elle ne dépend pas d'un échantillon fixe du début.
Après un rejet par `-w`, la reprise conserve le début de la ligne courante
pour respecter les frontières de mots, sans retraiter les enregistrements
antérieurs déjà écartés. Le découpage parallèle de `parallelLiteralCount`
reste en place ; chaque worker applique cette stratégie à son morceau.

Le coût reste **O(N) pour ces motifs bornés**, avec mémoire supplémentaire
**O(1) par worker**. Le gain vient du travail évité par ligne, pas d'un
changement d'ordre de complexité. Un repli peut reparcourir le début de la
ligne courante, donc des enregistrements adverses très longs restent une limite.
Les motifs vides, longs, contenant le séparateur et les comptages inversés
conservent le chemin régulier.

Dans les microbenchmarks sur tampon déjà en mémoire, le comptage rare passe
cette fois de **6,27 à 4,73 ms**, soit environ **25 % de temps interne en moins**.
La détection NUL reste autour de 3,7 ms et le formatage numéroté autour de
5,7 ms. Ces fonctions sont mesurées séparément et leurs temps ne s'additionnent
pas pour reconstituer le temps total.
[Microbenchmarks](performance-counting-2026-11-11/final-micro.json).

### Vérifications, régressions secondaires et limites

Les six distributions supplémentaires couvrent : rare puis dense, dense puis
rare, une ligne sélectionnée sur huit, mots rejetés, lignes longues et préfixe
sans résultat suivi de mots rejetés. Le premier candidat ralentissait le dernier
cas avec `-w` ; le point de reprise a été corrigé avant de retenir le second.

Les rapports appariés indiquent quatre petites régressions statistiquement
établies dans ces séries de 11 tours :

| Distribution / opération | Temps supplémentaire apparié |
|---|---:|
| Dense puis rare, comptage inversé du motif rare | 1,9 % |
| Dense puis rare, comptage inversé de `INFO` | 1,1 % |
| Une ligne sur huit, comptage inversé de `INFO` | 2,3 % |
| Mots rejetés, comptage dense de `INFO` | 1,8 % |

Le correctif est retenu localement pour son gain de 12 à 15 % sur les cas ciblés,
en exposant ces pertes. Il ne constitue pas une optimisation sans aucun
compromis. La disposition du code et la fréquence sont des explications
possibles pour les variations hors du chemin modifié ; leur part exacte n'a
pas été établie par un profil matériel.

Validation du **code retenu**, distincte de celle du premier prototype :

- **86/86 tests unitaires ReleaseFast**, **43/43 ReleaseSafe**, différentiels
  CLI/streaming, 59 cas regex et 141 cas de locales réussis.
- **3 072 contrôles de fuzzing** et **44 contrôles GNU sur gros fichiers
  newline/NUL**, deux moteurs et quatre CPU, réussis.
- Les nouveaux tests confrontent le compteur à une référence par enregistrement
  sur **10 080 combinaisons par moteur**, ainsi que des transitions de densité,
  des mots rejetés et une dernière ligne sans terminateur.
- **6 248 contrôles** de résultats ou de sorties passent durant les benchmarks.
  Les binaires qualifiés sont identiques à ceux mesurés ; les recettes des six
  distributions reproduisent exactement leurs empreintes.

Les scripts, échantillons, empreintes et essais écartés sont dans le
[dossier de preuves](performance-counting-2026-11-11/README.md). La CI distante
n'a pas été exécutée. Ces mesures concernent une machine et des corpus ASCII
chauds ; elles ne qualifient pas tous les motifs, fréquences ou fichiers réels.

---

**Historique du premier audit :** les sections suivantes conservent les mesures
et l'explication initiales, avant le comptage adaptatif ci-dessus. Le premier
prototype y reste écarté ; il ne faut pas le confondre avec le correctif retenu.

## Temps total et comparaison

**Le temps total est d'environ 15,6 ms pour les deux cas concernés en mode
normal, contre 12,5 à 13,7 ms pour ripgrep.** Les chiffres internes de 6,3 ms,
3,6 ms et 1 ms décrits plus bas ne sont pas trois parts de ce même total.

Conditions : **93,8 Mo, un million de lignes**, données en cache, un CPU
logique, `zgr` compilé en **ReleaseFast avec LLVM**. Les valeurs ci-dessous
sont les médianes de quinze exécutions après deux échauffements. Elles
incluent le lancement du programme et la sortie vers un fichier ordinaire.
`zgr de référence` désigne le moteur de référence, sans le patch expérimental.

| Opération complète | zgr de référence | ripgrep — Rust | GNU grep — C |
|---|---:|---:|---:|
| Compter les lignes contenant le littéral rare (`-F -c rare-needle`) | **15,64 ms** | 13,74 ms | 36,02 ms |
| Afficher les correspondances rares avec leur numéro (`-F -n rare-needle`) | **15,62 ms** | 12,50 ms | 38,72 ms |
| Même sortie, avec `-a` pour tous — texte imposé | **11,09 ms** | 12,11 ms | 37,80 ms |

Les deux premières lignes utilisent le mode `auto`, sans `-a` pour aucun
outil ; la troisième utilise le mode `text`, avec `-a` pour tous.
[Mesures complètes](performance-audit-2026-11-11/application-final.json).

Les trois chiffres internes ont une autre portée :

- **6,3 ms** : temps de **toute la fonction de comptage littéral rare** sur
  le tampon en mémoire, pas du seul travail inutile sur les fins de ligne.
  Le prototype descend à **5,41 ms** dans ce microbenchmark.
- **3,6 ms** : temps de la détection des octets NUL mesurée isolément sur
  le tampon en mémoire. Elle concerne certaines sorties ; **cette préanalyse
  n'est pas exécutée dans le cas `-c`**.
- **1 ms supplémentaire** : différence entre recherche/formatage **sans
  numéros, 4,76 ms**, et **avec numéros, 5,77 ms**, dans le microbenchmark.

**Ces trois chiffres ne s'additionnent pas.** Les fonctions sont mesurées
séparément, sur des chemins différents, sans lancement du processus ni E/S
fichier ; la sortie du formatage est jetée. Ils ne permettent pas non plus
de calculer une part exacte du temps total ou un gain entièrement récupérable.
[Mesures internes](performance-audit-2026-11-11/micro-final.json).

Aucune mesure interne équivalente de ripgrep n'a été réalisée : **la
comparaison avec Rust porte sur l'exécution complète**. Les microbenchmarks
comparent les fonctions de `zgr` actuel à celles du prototype.

## Résultat du premier essai d'optimisation

Trois coûts ressortent : le traitement des fins de ligne pendant le comptage
littéral, la préanalyse binaire avant certaines sorties et le parcours des
séparateurs pour numéroter les lignes. Le premier a fait l'objet d'un
prototype : **10 à 15 % de réduction dans les microbenchmarks ciblés**, mais
un gain plus variable, d'environ **2 à 8 %**, dans l'exécutable complet.
La série complète révèle aussi une **régression d'environ 4 % sur le comptage
dense**. Le prototype n'est donc **pas intégré au moteur** ; son patch et ses
preuves sont conservés pour poursuivre l'étude.

Le protocole précédent passait `-a` à ripgrep seul, ce qui l'avantageait sur
les sorties de lignes où `zgr` préanalyse les octets NUL. `zgr -c` évite déjà
cette préanalyse : elle n'explique pas les écarts de comptage. Le comparateur
maintenu applique désormais le même mode d'entrée à tous les outils et inclut
un comptage littéral dense pour détecter ce type de régression.

Ce premier audit a ajouté les microbenchmarks et conservé son prototype sous
forme de patch. À son terme, les sources applicatives étaient revenues à la
référence. La nouvelle optimisation décrite en tête de document a été réalisée
ensuite ; les données de cette première campagne restent intactes.

## Périmètre et méthode

Base : `0201712675658054ff7cf3a18bec61331bb43a5e`. Les sources applicatives et
les empreintes des exécutables de référence ont été vérifiées contre la capture
du benchmark précédent avant modification. Le prototype final ajoute le patch
archivé de `src/scanner.zig`. Zig 0.16.0, ReleaseFast, LLVM, CPU raptorlake,
zpcre2 épinglé dans `build.zig.zon`.

Références externes : ripgrep 15.2.0 et GNU grep 3.11 installés. Leurs versions
et empreintes sont enregistrées. L'étude compare des outils et leurs chemins
d'exécution ; elle n'isole pas la vitesse intrinsèque de Zig ou Rust.

Corpus ASCII newline généré : 1 000 000 lignes, 93 789 827 octets,
SHA-256 `da9fd9c2df9698ffcbeac1693c0fdf72b9357ff50fc0234c4e1d1f3f13797a3b`.
Locale C, données en cache. La série principale utilise le CPU logique 2,
deux échauffements et quinze tours appariés à ordre aléatoire. Tous les
threads héritent de l'affinité. La sortie est un fichier ordinaire sans
`fsync` ; le lancement du processus est inclus. La fréquence n'est pas
verrouillée : les comparaisons appariées sont préférables aux différences
entre séries exécutées à des moments distincts.

`perf stat -e task-clock true` est refusé (`perf_event_paranoid=4`). Aucun
profil matériel n'a donc été obtenu. Le microbenchmark appelle directement
les vraies fonctions Zig depuis une bibliothèque, sur un tampon déjà en
mémoire, avec 25 tours appariés et deux échauffements. Il exclut l'ouverture,
le mapping, les défauts de page initiaux et le lancement. Le formatage écrit
vers `Writer.Discarding`. Chaque résultat est contrôlé contre Python ou GNU grep.

Le scanner du skill `complexity-optimizer` ne prend pas Zig en charge. Ses
alertes concernent surtout les scripts de mesure ; les conclusions ci-dessous
reposent sur la lecture des chemins Zig et les mesures internes.

## Sections les plus coûteuses et priorités

Les lignes ci-dessous désignent le moteur de référence, sans le patch expérimental.

| Priorité | Section | Coût et complexité actuels | Optimisation envisagée, preuve et risque |
|---|---|---|---|
| 1 | `src/scanner.zig:2160`, `countLiteralSelected`, puis `countLiteralLines` à 2305 | Parcours SIMD de N octets, traitement de L séparateurs et C candidats : O(N/32 + L + C×M), linéaire pour M borné à 32. Environ 6,30 ms pour le comptage rare. | Éviter les événements de ligne sans candidat : même O(N), moins de travail. Gain interne confirmé, mais régression dense dans l'application ; patch non intégré. Risques : frontières SIMD, inversion et dernier enregistrement. |
| 2 | `src/main.zig:1813`, `scanRegularBuffer`, et `src/scanner.zig:1559`, `findNulParallel` | Préparcours O(N) avant certaines sorties, environ 3,60 ms en mémoire. `shouldSummarizeBinary` à 2027 exclut notamment `-c`. | Étudier une détection fusionnée avec la recherche, toujours O(N). Risque élevé : sémantique binaire GNU, sortie partielle, position du NUL et diagnostics. Aucune suppression de vérification. |
| 3 | `src/scanner.zig:2599`, `scanLiteralFast`, et `selectedOutputWorker` à 1992 | Comptage des séparateurs sur les intervalles ignorés ; ceux-ci ne se recouvrent pas. O(N), pas O(N²). Sortie rare : 4,76 ms sans numéros, 5,77 ms avec numéros. | Partager le masque de séparateurs avec la recherche, même O(N), moins de lectures. Risques : numéros, limites des chunks et dernier enregistrement. Pas de correctif évalué ici. |
| 4 | `src/matcher.zig:1031`, `Literal.findVectorized` | Filtre premier/dernier octet par blocs de 32, puis vérification : O(N/32 + C×M), pire cas O(N×M). M est borné sur ce chemin. | Mesurer les faux candidats avant de changer les octets filtrants ou le déroulage. Le coût sur de longs motifs n'est pas établi par ce corpus. |
| 5 | `src/scanner.zig:2868`, `shouldUseRegexPrefilter` | Échantillonnage d'au plus 1 Mio avant le parcours réel : coût borné supplémentaire. | Garder les heuristiques tant qu'un gain reproductible sur plusieurs distributions n'est pas établi. Le prototype utilise cette sonde pour choisir sa stratégie de comptage. |

Le microbenchmark importe le véritable module zpcre2. Les fonctions littérales
mesurées sont communes à `zgr` et `zgrc`. `std.mem.countScalar` utilise déjà
une voie vectorisée ; remplacer ce comptage par une boucle scalaire serait
une mauvaise hypothèse de départ.

## Microbenchmarks du prototype final

Médianes en millisecondes ; plus petit = plus rapide. Ces mesures séparées ne
s'additionnent pas en une décomposition exacte du temps de l'exécutable.

| Fonction / charge | Moteur de référence | Prototype | Réduction du temps |
|---|---:|---:|---:|
| Comptage du littéral rare | 6,304 | 5,408 | 14,2 % |
| Comptage du littéral absent | 6,388 | 5,420 | 15,2 % |
| Comptage de mots entiers | 6,361 | 5,394 | 15,2 % |
| Comptage sans distinction de casse | 6,709 | 6,018 | 10,3 % |
| Comptage littéral dense | 8,248 | 7,475 | 9,4 % |
| Détection NUL | 3,600 | 3,626 | pas de gain |
| Détection ASCII | 3,664 | 3,716 | pas de gain |
| Comptage des sauts de ligne | 3,238 | 3,229 | stable |
| Recherche des occurrences | 4,682 | 4,648 | stable |
| Recherche + sortie peu dense sans numéros | 4,763 | 4,794 | stable |
| Recherche + sortie peu dense numérotée | 5,772 | 5,789 | stable |

Les 648 appels contrôlés passent, pour douze noyaux et deux bibliothèques.
La longueur produite est vérifiée pour le formatage ; les comparaisons des
exécutables vérifient en plus le SHA-256 de toute la sortie.
[Mesures internes](performance-audit-2026-11-11/micro-final.json).

## Effet sur l'exécutable, face à ripgrep

Mode `auto` : aucun outil ne reçoit `-a`. Extrait de la série complète, en ms :

| Cas | zgr de référence | Prototype | ripgrep |
|---|---:|---:|---:|
| Littéral absent | 15,793 | 15,122 | 13,627 |
| Littéral rare | 15,636 | 15,372 | 13,737 |
| Mot entier | 15,813 | 15,356 | 13,971 |
| Sans distinction de casse | 15,972 | 15,617 | 17,242 |
| Regex avec suffixe | 14,016 | 14,039 | 13,576 |
| Sortie numérotée peu dense | 15,622 | 15,663 | 12,504 |
| Comptage littéral dense | 19,538 | 20,228 | 49,539 |
| Sortie numérotée dense | 58,136 | 58,617 | 168,932 |

Les rapports appariés confirment un petit gain sur les quatre comptages ciblés
en mode `auto`. Pour le comptage dense, le ratio référence/prototype est
**0,963**, intervalle bootstrap à 95 % **[0,958 ; 0,970]** : la régression
est établie dans cette série. Le programme reste largement devant ripgrep
sur ce cas, mais ce n'est pas une raison pour accepter la régression.

Mode `text` : tous les outils reçoivent `-a`. Le comptage absent passe de
11,885 à 10,997 ms, face à 10,088 ms pour ripgrep. La sortie numérotée peu dense
donne 11,092 ms pour le moteur de référence, 11,010 ms pour le prototype et 12,111 ms
pour ripgrep. Cette inversion du classement par rapport au mode `auto`
souligne le coût de la gestion binaire ; elle ne provient pas du correctif
de comptage. Plusieurs autres gains apparents en mode texte ont un intervalle
apparié qui inclut l'absence de gain.

Les 1 615 vérifications de sortie et de statut passent : référence, prototype,
`zgrc`, ripgrep et GNU grep ; treize cas `auto` et six cas ciblés `text`.
Les JSON conservent aussi les mesures complètes de `zgrc` et GNU grep.
[Mesures des exécutables](performance-audit-2026-11-11/application-final.json).

## Essais et décision

Le premier essai remplace l'énumération des séparateurs par un comptage de bits
dans les blocs sans candidat. Son gain sur les comptages rares reste faible.
Une spécialisation qui évite aussi le calcul du total lorsque `-v` est absent
améliore davantage les noyaux, mais régresse sur le cas dense. Un changement
d'alignement seul ne résout pas le problème.

Le prototype final sélectionne cette spécialisation seulement lorsque la
sonde existante estime le motif peu fréquent. Un contrôle dense isolé à
25 tours donne 13,249 ms avant et 13,282 ms après, sans régression établie
(intervalle du ratio [0,978 ; 1,013]). Pourtant la série complète suivante
retrouve la régression décrite plus haut. Le bénéfice interne ne suffit donc
pas à qualifier le changement. Fréquence, disposition du code et autres
effets restent des hypothèses ; aucun profil matériel ne permet ici de
départager leurs contributions.

Le [patch expérimental](performance-audit-2026-11-11/literal-count-prototype.patch)
contient le prototype final et ses tests différentiels. Il n'est pas appliqué.
Les essais antérieurs restent dans `experiments/` ; leurs résultats ne doivent
pas être attribués au prototype final ni au moteur de référence.

La priorité issue de ce premier audit était de stabiliser le comptage sur
plusieurs densités et dispositions de lignes. L'optimisation décrite en tête
de document reprend cette piste. La fusion du comptage des séparateurs pour
la numérotation et celle de la détection NUL restent des travaux distincts,
avec des tests dédiés aux sorties et à la compatibilité binaire.

## Reproduire les mesures internes et globales

```sh
zig build -Doptimize=ReleaseFast -Dllvm=true
zig build bench-internal -Doptimize=ReleaseFast -Dllvm=true
bench/generate.sh /tmp/zgrep-audit.txt 1000000
python3 bench/internal.py --library zig-out/lib/libzgrep-internal-bench.so \
  --corpus /tmp/zgrep-audit.txt --cpu 2 --repeats 25 \
  --output /tmp/zgrep-internal.json
python3 bench/compare.py --corpus /tmp/zgrep-audit.txt --cpu 2 \
  --input-mode auto --repeats 15 --output /tmp/zgrep-auto.json
python3 bench/compare.py --corpus /tmp/zgrep-audit.txt --cpu 2 \
  --input-mode text --repeats 15 --output /tmp/zgrep-text.json
```

Utiliser un CPU autorisé et de nouveaux chemins JSON. `--baseline-library`
alterne une bibliothèque de référence et le candidat dans chaque tour. Pour
rejouer le prototype, appliquer le patch dans une copie isolée de la référence
avec ces outils, puis compiler vers un préfixe séparé. Les scripts archivés
conservent les chemins exacts de l'expérience.

## Validation et limites

Le **prototype**, avant son retrait, a passé :

- 84/84 tests unitaires ReleaseFast et 42/42 tests ReleaseSafe.
- Un test différentiel sur 29 952 combinaisons par moteur : frontières SIMD,
  séparateurs newline/NUL, casse, mots, motif vide et dernier enregistrement
  sans terminateur ; sélection de stratégie et inversion également contrôlées.
- Les différentiels CLI et streaming, 59 cas regex, 141 cas de locales et
  3 072 vérifications de fuzzing.
- Les 648 vérifications internes et 1 615 vérifications des exécutables citées.

Les nouveaux outils sont également compilés et vérifiés avec le **moteur
actuel sans patch** ; leurs résultats distincts figurent dans le dossier de
preuves. Les microbenchmarks rejoignent l'étape ReleaseFast de la CI. Le
workflow modifié n'a pas été exécuté à distance pour ce lot.

Les résultats portent sur une machine et un corpus synthétique ASCII chaud.
Ils ne qualifient pas à eux seuls les caches froids, les arbres de petits
fichiers, les données Unicode, les longs motifs ou les distributions adverses.
