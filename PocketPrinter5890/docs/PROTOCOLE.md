# PocketPrinter (ex-L13ReceiptPrinter) - contexte complet et mega prompt

Derniere mise a jour: 2026-08-19 (revision majeure)

> **AVERTISSEMENT - REVISION MAJEURE DU 2026-08-19**
>
> La version precedente de ce document decrivait une imprimante **L13 a etiquettes de 14 mm / 96 px**,
> sur la base de l'article de retro-ingenierie d'atctwo. **Ce n'est PAS le materiel de l'utilisateur.**
>
> Le materiel reel est une **mini imprimante de poche a ticket de caisse, papier 56 mm**,
> de la famille generique **5890**, largeur d'impression **384 px = 48 octets par ligne**.
>
> L'ancienne consigne "ne jamais utiliser 384 px, la largeur est 96 px" est annulee: elle
> rendait tout raster inexploitable. Elle n'etait cependant pas la seule cause du blocage.
> Meme corrigee, rien ne s'imprimait sans la sequence d'activation LuckPrinter decrite
> plus bas, qui manquait egalement. Toute copie de l'ancien document doit etre ignoree.
>
> Sauvegarde de l'ancienne version: `MEGA_PROMPT_L13.md.bak`.
>
> **MISE A JOUR DU 2026-08-19 (soir) - IMPRESSION CONFIRMEE**
>
> Le modele reel a ete lu sur la machine: **A2Y, firmware V1.06LY** (pas DP-L13/V3.05).
> L'APK officielle `com.printer.lidloffice` a ete decompilee: elle embarque le
> **LuckPrinter SDK**, et le nom BLE "Mini Pocket Printer" mappe sur la classe
> `MiniPocketPrinter extends DP_D1`, qui teste explicitement `"A2Y"`.
>
> **La cause du blocage etait l'absence de la sequence d'activation LuckPrinter.**
> Sans elle, le firmware acquitte chaque commande par `01 01` et n'execute rien,
> pas meme une avance papier. L'avance papier et la mire 384 px ont ete
> **confirmees physiquement** par l'utilisateur apres ajout de cette sequence.

## Objectif du projet

Creer une **librairie reutilisable** plus une application macOS 13+ SwiftUI pour piloter directement
une mini imprimante thermique de poche SilverCrest / Tronic (Lidl) en Bluetooth Low Energy,
sans passer par l'application officielle Pocket Printer et sans service cloud.

La librairie doit permettre d'imprimer:

- du texte (avec gras, alignement, taille, souligne);
- des images (bitmap, dithering);
- des codes-barres et QR codes;
- des tickets de caisse composes.

Elle doit rester independante du transport pour permettre plus tard:

- Bluetooth Classic SPP/RFCOMM;
- USB Printer;
- une CLI;
- une integration Home Assistant ou autre automatisation locale.

CoreBluetooth ne gere pas le Bluetooth Classic SPP/RFCOMM. Le projet ne doit pas pretendre faire du SPP
dans cette version.

## Chemin local

Projet:

```text
/Users/iachi.dimitri/Projets/L13 Tronic lLIDL/L13ReceiptPrinter
```

Log persistant de l'application sandboxee:

```text
/Users/iachi.dimitri/Library/Containers/local.L13ReceiptPrinter/Data/Library/Logs/L13ReceiptPrinter/ble.log
```

Le chemin non sandboxe `/Users/iachi.dimitri/Library/Logs/L13ReceiptPrinter/ble.log` n'est pas celui
utilise par l'application lancee via Xcode: le sandbox macOS place les donnees dans le conteneur.

## Imprimante cible - FAITS CONFIRMES

Materiel de l'utilisateur:

- Marque commerciale: **SilverCrest / Tronic (Lidl)**, IAN 508705 2507.
- Achat: Lidl. Design identique entre la version SilverCrest et la version Tronic, meme application officielle.
- Fiche produit: https://www.lidl.fr/p/silvercrest-mini-imprimante-de-poche/p100390313
- Famille generique: **5890** (mini imprimante thermique de poche).
- Batterie: Li-Ion 18500, 3,7 V, 1200 mAh, 4,44 Wh.
- Connexion: Bluetooth 5.0 et USB-C.
- Resolution: **203 dpi**.
- Papier: **thermique continu type ticket de caisse, largeur ~56 mm, rouleau de 7,8 m**.
  Consommable Lidl associe: https://www.lidl.fr/p/tronic-papier-photo-pour-mini-imprimante-de-poche-3-pieces/p100406311
- **Largeur d'impression: 384 pixels = 48 octets par ligne.** C'est la zone imprimable standard
  (48 mm utiles sur 56 mm de papier) de toute la famille 5890.
- Nom BLE observe: `Mini Pocket Printer_BLE`.
- UUID macOS observe: `759ACF04-8D4E-CA6B-DB61-3189407E8DBC`.

**Fait de validation essentiel: l'application officielle Pocket Printer imprime correctement
depuis le telephone de l'utilisateur.** Le materiel, le papier et son insertion sont donc sains.
Tout echec d'impression du projet est un bug logiciel, jamais un probleme materiel.

### Ce que le materiel n'est PAS

- **Ce n'est pas une L13 a etiquettes.** La L13 documentee par atctwo est une imprimante
  d'etiquettes de 14 mm de large, 96 px, 12 octets par ligne. Modele different.
- Le nom de modele `DP-L13` provient de l'article atctwo, **pas** d'une reponse de cette machine.
  La machine repond `A2Y` a `10 FF 20 F0` et `V1.06LY` a `10 FF 20 F1`: le
  modele est donc etabli, et ce n'est pas une DP-L13.
- Ne jamais reintroduire 96 px comme largeur par defaut. 96 px doit rester au mieux une option
  de compatibilite pour d'autres machines.

## Largeur raster - regle normative

```text
Largeur par defaut: 384 pixels
Octets par ligne:   48
Header raster 384 x N:  1D 76 30 00 30 00 <yL> <yH>
```

Exemple pour 384 x 240:

```text
1D 76 30 00 30 00 F0 00
Charge utile: 48 * 240 = 11520 octets
```

Largeurs alternatives a exposer en option uniquement (autres machines):

| Largeur px | Octets/ligne | xL xH | Usage |
|---|---|---|---|
| 384 | 48 | `30 00` | **defaut, machine de l'utilisateur** |
| 576 | 72 | `48 00` | imprimantes 80 mm |
| 96  | 12 | `0C 00` | L13 etiquettes 14 mm, compatibilite seulement |

## Services BLE

Services observes sur la machine:

Interface FF00 - **celle qui fonctionne et qui repond**:

```text
Service: FF00
TX notifications: FF01
RX write: FF02
Extra notifications: FF03
```

Interface Microchip Transparent UART:

```text
Service: 49535343-fe7d-4ae5-8fa9-9fafd205e455
TX notifications: 49535343-1e4d-4bd9-ba61-23c647249616
RX write without response: 49535343-8841-43f4-a8d4-ecbe34729bb3
Extra: 49535343-aca3-481c-91ec-d85e28a60318
```

Interface 18F0:

```text
Service: 18F0
TX notifications: 2AF0
RX write without response: 2AF1
```

Interface e781:

```text
Service: e7810a71-73ae-499d-8c15-faa9aef0c3f2
TX/RX combines: bef8d6c9-9c21-4c9e-b632-bd58c1009f9f
```

Observation locale: `FF00/FF02` avec notifications sur `FF01` **et** `FF03` est le canal qui repond.
Le mode automatique doit essayer FF00 en premier. Transparent UART se connecte mais reste souvent muet.

**Important: FF01 porte des reponses utiles et a longtemps ete sous-exploite.**
Reponses reellement observees sur FF01:

```text
RX FF01: 4F 4B   -> ASCII "OK"  (acquittement d'une commande, ex. reglage de densite)
RX FF01: 00      -> reponse a "10 FF 40", papier present
```

## Sequence d'activation obligatoire (LuckPrinter)

Extraite de `DP_D1.printTagOnce()` dans l'APK officielle. **Sans elle, rien ne s'execute.**

```text
Avant le travail:
  10 FF F1 03                                  enablePrinterLuck (mode 3)
  00 x12                                       printerWakeupLuck (commande SEPAREE)
  1F 80 01 20                                  setPaperType(1, 32) papier continu

Contenu:
  1D 76 30 00 30 00 yL yH <pixels>             raster par bandes

Apres le travail:
  1B 64 n                                      avance
  1D 0C                                        printerPositionLuck
  10 FF F1 45                                  stopPrintJobLuck
```

Attention: les 12 zeros de reveil sont une **commande distincte**, pas un bourrage
accole a `10 FF F1 03`. Plusieurs documentations publiques se trompent sur ce point.

Note non encore exploitee: `MiniPocketPrinter` appelle `setCompress(true)` quand le
modele vaut `A2Y`. Le SDK sait donc envoyer un raster compresse. Le raster **non
compresse** fonctionne (mire confirmee), la compression reste optionnelle et
n'a pas ete implementee.

## Commandes

Commandes proprietaires (confirmees sur cette machine):

Referentiel complet des vingt commandes proprietaires du SDK, verifie octet
par octet contre `BaseNormalDevice`:

```text
LECTURE
Modele:             10 FF 20 F0        -> "A2Y"
Firmware:           10 FF 20 F1        -> "V1.06LY"
Numero de serie:    10 FF 20 F2
Bootloader:         10 FF 20 EF
Vitesse:            10 FF 20 A0
Batterie:           10 FF 50 F1        -> 00 nn, nn = pourcentage
Etat papier:        10 FF 40
Densite:            10 FF 11
Extinction auto:    10 FF 13           -> deux octets, gros-boutiste
Format horaire:     10 FF B0
Reglages:           10 FF 70

ECRITURE
Densite:            10 FF 10 00 n      n = 0 faible, 1 moyenne, 2 forte
Extinction auto:    10 FF 12 hi lo     DEUX octets, gros-boutiste
Largeur:            10 FF 15 lo hi     petit-boutiste
Vitesse:            10 FF C0 n
Mode:               10 FF 30 27 n
Reset usine:        10 FF 04
Horloge:            10 FF 53 4A f + AAAA MM JJ hh mm ss
Chauffe:            1F 70 01 n
Plateforme:         FC FF 00 02 45 02 00 46

CYCLE D'IMPRESSION
Activation:         10 FF F1 03
Reveil:             00 x12             commande distincte
Type de papier:     1F 80 type len
Calage:             1D 0C
Fin de travail:     10 FF F1 45
```

Deux pieges d'encodage releves en comparant au SDK:

- `10 FF 12` (extinction) prend **deux** octets, gros-boutiste `(n/256, n%256)`.
  Une implementation a un seul octet plafonne a 255 minutes et decale la valeur.
- `10 FF 53 4A` (horloge) prefixe les sept octets de date. Envoyer la date
  seule ne produit rien.

Notez l'inversion d'ordre entre `10 FF 12` (gros-boutiste) et `10 FF 15`
(petit-boutiste): le SDK n'est pas homogene sur ce point.

Le reglage de densite `10 FF 10 00 01` recoit `OK` sur FF01, ce qui confirme
que la famille `10 FF ...` est comprise. Les commandes de lecture repondent
sur FF01 apres une trame de credit `01 nn`.

Aucune commande d'extinction a distance n'existe dans le SDK: les vingt
commandes ci-dessus ont ete passees en revue. Une machine eteinte ne pouvant
plus etre reveillee par BLE, la fonction serait sans retour.

Commandes ESC/POS standard - **socle a privilegier**, la machine est une 5890 generique:

```text
Init:               1B 40
Raster:             1D 76 30 m xL xH yL yH <pixels>
Avance n points:    1B 4A n
Avance n lignes:    1B 64 n
Form feed:          0C
Alignement:         1B 61 n     (0 gauche, 1 centre, 2 droite)
Gras:               1B 45 n     (0 off, 1 on)
Souligne:           1B 2D n
Taille caractere:   1D 21 n     (quartet haut = largeur, bas = hauteur)
Mode caractere:     1B 21 n
Interligne defaut:  1B 32
Interligne n:       1B 33 n
Jeu de caracteres:  1B 74 n     (page de code)
Code-barres:        1D 6B m ...
QR code:            1D 28 6B ...
Statut temps reel:  10 04 n
```

Sequence d'impression recommandee:

```text
1. Init:            1B 40
2. Densite:         10 FF 10 00 01
3. Raster par bandes: 1D 76 30 00 30 00 <hauteur bande> 00 <donnees>
4. Avance finale:   1B 64 03  ou  1B 4A 28
```

Commandes experimentales de l'ancienne doc, **a ne pas activer par defaut**:

```text
Pre-impression: 10 FF F1 03 + 12 octets 00
Fin observee:   10 FF F1 45
```

## Format raster

```text
1D 76 30 m xL xH yL yH <pixels>
```

- `m = 00` mode normal;
- `xL/xH`: nombre d'octets par ligne, little-endian. **48 = `30 00`**;
- `yL/yH`: nombre de lignes, little-endian;
- 1 bit par pixel, **MSB-first**, bit a 1 = point noir;
- la hauteur est libre, le papier est continu.

**Envoi par bandes obligatoire.** Ne pas envoyer un raster de plusieurs milliers d'octets en un
seul bloc: le firmware perd des donnees. Decouper en bandes de 24 a 64 lignes, chaque bande etant
une commande `1D 76 30` complete et autonome. C'est la methode utilisee par toutes les
implementations qui fonctionnent sur cette famille.

## Ce qui ne fonctionne pas sur ce firmware

Section destinee a qui reimplemente le protocole dans un autre langage. Ces
limites ont ete etablies par impression physique, pas deduites du code: les
commandes concernees font partie du standard ESC/POS et paraissent legitimes,
mais le firmware A2Y ne les honore pas. Les essayer fait perdre du temps et,
pour certaines, gaspille du papier.

### ESC t, pages de code — IGNOREE

Une mire imprimant les memes six octets accentues apres chacune des neuf
commandes `ESC t 0` a `ESC t 19` a produit **neuf lignes rigoureusement
identiques, toutes illisibles**. Le firmware ne change jamais de table.

Pire, il laisse un octet parasite s'imprimer: apres `1B 74 13`, un `a` isole
apparait devant la ligne suivante. Ne pas emettre cette commande du tout.

### Caracteres non-ASCII — NON GERES

Consequence directe de ce qui precede. `°`, `é`, `è`, `à`, `û`, `ç` sortent
en carre plein, quelle que soit la page de code declaree. Seul l'ASCII 0x20
a 0x7E est rendu.

Contournement retenu: transliteration avant envoi (`18°C` devient `18degC`,
`café` devient `cafe`, `12 €` devient `12 EUR`). Un texte legerement
approximatif vaut mieux qu'un carre illisible.

### GS ( k, QR code natif — NON IMPLEMENTEE

La commande s'imprime **en clair**, sous forme de texte. Trace reelle relevee
sur un ticket:

```text
k1A2k1Ck1E1k1P0https://exemple.fr/meteok1Q0
```

Le `k` est l'octet `0x6B` de `GS ( k`; le firmware ne reconnait pas la
commande et recrache la sequence entiere comme du texte.

### GS k, code-barres natif — NON IMPLEMENTEE

Meme comportement:

```text
<I{BMETEO2026
```

### GS B, inversion video — NON IMPLEMENTEE

Aucun effet visible: le texte sort en noir sur blanc comme d'habitude.

### Consequence: les codes doivent etre rasterises

L'application officielle ne procede pas autrement. Son SDK n'expose
**aucune** fonction d'impression de texte ni de code: tout est rendu en
bitmap cote telephone, puis envoye par `1D 76 30`. Une recherche de `GS k`
et `GS ( k` dans l'integralite du SDK et de l'application ne donne aucune
occurrence.

Autrement dit, le mode texte natif fonctionne mais reste hors des sentiers
battus par le fabricant; les codes n'ont pas d'autre voie que l'image.

### Pieges qui ne sont pas des limites du firmware

A ne pas confondre avec ce qui precede: ces points ont l'apparence de bugs
materiels mais viennent de l'implementation.

| Symptome | Cause reelle |
|---|---|
| Ligne coupee en plein mot (« l'apres-m » / « idi. ») | Ligne depassant 32 colonnes; le firmware coupe au caractere pres. Decouper en amont. |
| Rien ne s'imprime, tout est acquitte | Sequence d'activation absente. |
| Impression tres lente, millimetre par millimetre | Credits de flux ignores, paquets de 20 octets. |
| Papier qui defile longuement apres l'impression | `1F 80` envoye sur du papier continu: declare une etiquette de longueur fixe. |
| Marges laterales asymetriques | Mecanique: la tete couvre 48 mm sur ~56 mm de papier. Non corrigeable. |

## Etat de validation des commandes

Trois niveaux, a lire avant de se fier a une commande.

### Verifiees par impression physique

```text
10 FF F1 03    activation          indispensable
00 x12         reveil              indispensable
10 FF F1 45    fin de travail      indispensable
1F 80 t l      type de papier      mode etiquette
1D 0C          calage              mode etiquette
1D 76 30 ...   raster              384 px, bandes de 24 lignes
1B 4A n        avance points
1B 64 n        avance lignes
1B 40          init
10 FF 10 00 n  densite             repond OK sur FF01
10 FF 20 F0    modele              repond "A2Y"
10 FF 20 F1    firmware            repond "V1.06LY"
10 FF 50 F1    batterie            repond 00 nn
10 FF 40       etat papier
1B 61 n        alignement
1B 45 n        gras
1D 21 n        taille de caractere
```

### Portees mais JAMAIS EXECUTEES

Extraites du SDK et fidelement transcrites, sans aucune verification sur
machine. Le SDK couvre plus de cent cinquante modeles: rien ne garantit que
l'A2Y les implemente. **Les utiliser sans les tester expose a des surprises.**

```text
10 FF C0 n           vitesse d'impression
1F 70 01 n           niveau de chauffe
10 FF 12 hi lo       extinction automatique       (voir reserve ci-dessous)
10 FF 13             lecture extinction auto
10 FF 30 27 n        mode d'impression
10 FF 04             reglages d'usine             DESTRUCTIF si supporte
10 FF 53 4A f + date horloge interne
10 FF B0             lecture format horaire
10 FF 15 lo hi       largeur d'impression
10 FF 20 F2          numero de serie
10 FF 20 EF          bootloader
10 FF 20 A0          lecture vitesse
10 FF 11             lecture densite
10 FF 70             lecture reglages
1B BB CC / BB / AA   marques de decoupe
1F 11 11 n           recul papier
1F 11 n              calage automatique
FC FF 00 02 45 02 00 46   declaration de plateforme
```

Reserve particuliere sur `10 FF 12`: la valeur `0` est proposee comme
desactivation de l'extinction automatique, par convention repandue. **Ce
comportement n'est pas verifie**; le firmware peut la refuser ou imposer un
plancher. Relire avec `10 FF 13` apres ecriture pour savoir ce qui a ete
retenu.

### Volontairement non portee

`updatePrinterLuck` — mise a jour du firmware, via `YXFirmwareUpdater`. Un
portage non teste qui echoue en cours d'ecriture laisse une machine
inutilisable. Le risque est sans commune mesure avec le benefice.

## Contribuer

Ce document decrit un seul exemplaire: **A2Y, firmware V1.06LY**. D'autres
declinaisons de marque ou revisions de firmware peuvent se comporter
differemment.

Les retours utiles, par ordre d'interet:

1. **Une commande de la liste « jamais executees » testee sur machine** —
   preciser le modele, le firmware, la commande et ce qui s'est passe.
2. **Un modele different** qui repond autre chose a `10 FF 20 F0`.
3. **Le raster compresse**: le SDK active `setCompress(true)` pour l'A2Y,
   ce qui suppose un encodage compresse non encore identifie.
4. **Le comportement USB-C**: l'imprimante reste-t-elle eveillee branchee?
   Absent du SDK comme des fiches produit.
5. **Le troisieme octet de la trame batterie** (`02 64 **00**`), ignore par
   le SDK. Le bit `isCharging` (0x20) du statut suggere qu'il pourrait
   signaler la charge, sans confirmation.

Toute correction d'une affirmation de ce document est bienvenue: plusieurs
diagnostics initiaux se sont reveles faux, et sont signales comme tels dans
la section des bugs.

## Bugs identifies le 2026-08-19 (analyse de ble.log, 1748 lignes)

### Bug 1 - largeur raster fausse (cause principale)

Le code envoyait `1D 76 30 00 0C 00 ...`, soit 12 octets par ligne = 96 px, a une machine qui
attend 48 octets par ligne = 384 px. L'imprimante recoit un raster inexploitable et n'imprime rien.

Historique des headers observes dans les logs:

```text
1D 76 30 00 18 00 68 01   -> 24 o/ligne = 192 px  (bug Retina, corrige)
1D 76 30 00 0C 00 F0 00   -> 12 o/ligne =  96 px  (faux: doc L13 erronee)
Attendu desormais:
1D 76 30 00 30 00 ...     -> 48 o/ligne = 384 px
```

### Bug 2 - file d'ecriture BLE tronquee silencieusement

Comptage reel des octets transmis par job:

```text
17:01:27  header annonce 12*180 = 2168 octets -> 20 octets envoyes    (2148 manquants)
16:51:06  header annonce 24*360 = 8648 octets -> 3980 octets envoyes  (4668 manquants)
```

Cause: dans `drainWriteQueue()`, lorsque `peripheral.canSendWriteWithoutResponse` est faux,
la fonction fait `return` sans rien replanifier. Le callback CoreBluetooth
`peripheralIsReady(toSendWriteWithoutResponse:)` **n'est pas implemente**, donc la file ne repart
jamais. Des que le buffer BLE sature, l'impression s'arrete definitivement au milieu du raster.

Correctif requis: implementer `peripheralIsReady(toSendWriteWithoutResponse:)` et y appeler
`drainWriteQueue()`.

### Bug 3 - reponses FF01 ignorees

`RX FF01: 4F 4B` = ASCII "OK" et `RX FF01: 00` = papier present n'etaient pas exploites.
Le decodeur classait par ailleurs `01 01` en "flags inconnus" alors qu'il s'agit tres probablement
d'un acquittement ou d'un etat busy/receiving normal, emis a chaque paquet recu.

### Bug 4 - interpretation du statut papier

`RX FF03: 01 04` etait affiche comme "papier absent". Or l'application officielle imprime
correctement avec le meme papier en place. Ce statut doit etre traite comme informatif et ne
jamais bloquer une impression.

## Portage du SDK et modes papier

`Sources/L13Core/LuckPrinterCommands.swift` porte l'ensemble du jeu de commandes du
LuckPrinter SDK; `Sources/L13Core/PocketPrinter.swift` en est la facade.

Distinction essentielle, issue du SDK:

```text
printOnce()     papier continu   -> PAS de 1F 80, PAS de 1D 0C
printTagOnce()  etiquettes       -> 1F 80 <type> <len> puis 1D 0C
```

Envoyer `1F 80` sur papier continu declare une etiquette de longueur fixe et fait
derouler du papier jusqu'a la fin de cette longueur. C'est le bug corrige le
2026-08-19 au soir.

`endLineDot` (avance de degagement) vaut 0 pour DP_D1 mais 50 a 144 selon les
modeles dans le SDK. Le projet utilise 80 points (~10 mm) par defaut pour sortir
le ticket de sous la tete d'impression.

## Controle de flux par credits

Les trames `01 nn` recues sur FF03 **ne sont pas des statuts**: ce sont des credits
de flux. Le SDK fait `credit.addAndGet(bArr[1] & 0xFF)` puis envoie jusqu'a
`credit` paquets d'affilee.

Consequence: `01 01` = 1 paquet disponible, `01 04` = 4 paquets. L'ancienne lecture
« papier absent » pour `01 04` etait fausse.

Reglages: paquets de 180 octets (le SDK negocie un MTU jusqu'a 512), pas de delai
fixe, reprise pilotee par les credits.

## Etat du projet local

```text
Sources/L13Core           modele de ticket, commandes, encodage raster, rendu, jobs
Sources/L13BLETransport   scan, connexion, GATT, profils UART, notifications, file d'ecriture
Sources/L13ReceiptPrinter application SwiftUI
Sources/L13BLEProbe       outil console de diagnostic BLE
Tests/                    tests unitaires
```

## Plan de travail

1. **Largeur 384 px par defaut** dans le rendu et l'encodeur, largeur configurable, 96 px en option.
2. **Corriger la file BLE**: implementer `peripheralIsReady(toSendWriteWithoutResponse:)`,
   detecter la fin de job, ne jamais abandonner un raster en cours.
3. **Envoi du raster par bandes** de 24 a 64 lignes.
4. **Librairie d'impression reutilisable**: texte (gras, alignement, taille), images avec dithering,
   codes-barres, QR codes, composition de tickets.
5. **Ameliorer le decodage des reponses**: exploiter FF01, traiter `OK`, `01 01`, `01 04` correctement.
6. **Init `1B 40`** en debut de job.
7. Mode diagnostic: mire de largeur, test de plusieurs largeurs pour confirmation visuelle.

## Regles de travail

- Travailler uniquement dans `/Users/iachi.dimitri/Projets/L13 Tronic lLIDL`. Executer `pwd` d'abord.
- Preserver les fichiers existants.
- Ne pas casser les tests. Lancer `swift test` et le build apres chaque changement.
- **Ne jamais affirmer que l'impression physique fonctionne sans que l'utilisateur l'ait observee.**
- Ne pas reintroduire la largeur 96 px par defaut.
- Ne pas affirmer que la machine est une DP-L13.

## Commandes utiles

```bash
cd "/Users/iachi.dimitri/Projets/L13 Tronic lLIDL/L13ReceiptPrinter"
swift test
xcodebuild -project L13ReceiptPrinterApp.xcodeproj -scheme L13ReceiptPrinterApp -destination 'platform=macOS' build
open "L13ReceiptPrinterApp.xcodeproj"
tail -n 200 "/Users/iachi.dimitri/Library/Containers/local.L13ReceiptPrinter/Data/Library/Logs/L13ReceiptPrinter/ble.log"
swift run L13BLEProbe
```

## Sources

Sources sur la famille 5890 / mini imprimantes de poche generiques - **pertinentes pour ce materiel**:

- https://github.com/ChiaraCannolee/thermal-pocket-printer-basic
- https://github.com/NaitLee/Cat-Printer
- https://github.com/Dejniel/TiMini-Print
- Reference ESC/POS Epson (socle standard des 5890)

Sources sur la L13 a etiquettes - **modele different, a titre historique uniquement**:

- https://github.com/atctwo/reverse-engineering/tree/main/l13-thermal-printer
- https://atctwo.net/posts/2024/07/16/thermal-printer.html

Ne pas appliquer les largeurs et specificites L13 (96 px, 14 mm, etiquettes) a cette machine.

## Mega prompt reutilisable

```text
Travaille directement et uniquement dans le dossier local courant:

/Users/iachi.dimitri/Projets/L13 Tronic lLIDL

Commence par executer pwd. Si le chemin ne commence pas par /Users/iachi.dimitri/Projets/,
arrete-toi sans creer de fichiers. Preserve tout fichier existant.

Projet a maintenir:
/Users/iachi.dimitri/Projets/L13 Tronic lLIDL/L13ReceiptPrinter

Application macOS 13+ SwiftUI/CoreBluetooth + librairie reutilisable pour piloter une mini
imprimante thermique de poche SilverCrest/Tronic (Lidl), IAN 508705, famille generique 5890.
Locale, sans cloud.

MATERIEL - FAITS CONFIRMES:
- Mini imprimante de poche a ticket de caisse, papier thermique continu ~56 mm, rouleau 7,8 m.
- 203 dpi. Batterie Li-Ion 3,7 V 1200 mAh. Bluetooth 5.0 + USB-C.
- LARGEUR D'IMPRESSION: 384 pixels = 48 octets par ligne. Header: 1D 76 30 00 30 00 yL yH.
- Nom BLE: "Mini Pocket Printer_BLE". UUID macOS: 759ACF04-8D4E-CA6B-DB61-3189407E8DBC.
- L'APPLICATION OFFICIELLE POCKET PRINTER IMPRIME CORRECTEMENT. Le materiel est sain.
  Tout echec d'impression est un bug logiciel.

CE QUE CE N'EST PAS:
- Ce n'est PAS une L13 a etiquettes 14 mm / 96 px. Ne jamais utiliser 96 px par defaut.
- Ne pas affirmer que le modele est DP-L13: aucune reponse de modele n'a jamais ete obtenue.
- Les specifications de l'article atctwo concernent un autre modele.

BLE:
- FF00 est le service qui fonctionne: RX write FF02, notifications FF01 ET FF03.
- FF01 porte des reponses utiles: 4F 4B = "OK", 00 = papier present.
- FF03 porte des statuts: 01 01 = ack/busy, 01 04 = statut papier (ne doit PAS bloquer
  l'impression), 02 64 00 = batterie 100%.
- Autres profils en repli: Transparent UART 49535343-fe7d-..., 18F0, e781.

COMMANDES:
- ESC/POS standard est le socle: 1B 40 init, 1D 76 30 raster, 1B 4A n avance,
  1B 61 n alignement, 1B 45 n gras, 1D 21 n taille, 1D 6B code-barres, 1D 28 6B QR.
- Proprietaires: 10 FF 10 00 n densite (repond OK), 10 FF 40 papier, 10 FF 50 F1 batterie.
- Le raster DOIT etre envoye par bandes de 24 a 64 lignes, jamais en un seul gros bloc.

BUGS CONNUS A NE PAS REINTRODUIRE:
1. Largeur raster 96 px au lieu de 384 px: cause principale de l'echec d'impression.
2. drainWriteQueue() abandonne la file quand canSendWriteWithoutResponse est faux.
   Il FAUT implementer peripheralIsReady(toSendWriteWithoutResponse:) et y relancer la file.
   Symptome: raster tronque, ex. 20 octets envoyes sur 2168 annonces.
3. Reponses FF01 ignorees.
4. Statut 01 04 interprete a tort comme un blocage.

Fichier de log a inspecter:
/Users/iachi.dimitri/Library/Containers/local.L13ReceiptPrinter/Data/Library/Logs/L13ReceiptPrinter/ble.log

PRIORITES:
1. Inspecter les logs et le code avant de modifier.
2. Largeur 384 px, configurable.
3. File BLE robuste, envoi par bandes.
4. Librairie reutilisable: texte, images, codes-barres, QR, tickets.
5. Ne pas casser les tests: swift test + xcodebuild apres chaque changement.
6. Ne JAMAIS dire que l'impression physique est validee sans observation reelle de l'utilisateur.
```
