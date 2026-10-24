# Imprimantes Brother dans l'application iOS

L'application iOS (`Examples/DemoAppIOS`) pilote aussi les imprimantes
Brother, en particulier la **TD-4550DNWB en Bluetooth Low Energy**, avec le
Brother Print SDK officiel pour iPhone et iPad.

> Le SDK n'est pas dans ce dépôt. C'est un binaire propriétaire Brother, et
> le dépôt ne redistribue aucun code constructeur. L'application compile sans
> lui; l'option Brother affiche alors « Brother Print SDK absent ».

## Le principe: l'imprimante d'abord, le papier ensuite

Le papier accepté dépend de l'imprimante. L'onglet **Connexion** suit donc
trois étapes:

1. **Imprimante**: Pocket 5890 (SilverCrest, Tronic, Parkside) ou Brother,
   puis le modèle Brother. La liste reprend les 93 modèles de
   `BRLMPrinterModel` (SDK 4.13), groupés par série, avec les interfaces
   iOS documentées pour chacun.
2. **Papier**, selon l'imprimante choisie:

   | Imprimante | Papier proposé |
   |---|---|
   | Pocket 5890 | largeur (58 mm par défaut) et mode continu/étiquettes |
   | Brother TD-4xxx | rouleaux 102/76/58 mm, étiquettes 102×152, 102×51, 51×26 mm, ou personnalisé jusqu'à 118 mm |
   | Brother TD-2xxx | rouleaux 58/51 mm, étiquettes 40×40, 51×26 mm, ou personnalisé |
   | Brother RJ-4/RJ-3/RJ-2 | rouleaux et étiquettes à la largeur de la série, ou personnalisé |
   | Brother QL | références DK que le SDK déclare compatibles avec le modèle |
   | Brother PT | largeurs de ruban que le SDK déclare compatibles avec le modèle |
   | Brother PJ | A4, Letter, Legal, A5 |
   | Brother MW | format imposé par le modèle |

   Pour les TD et RJ, trois types de papier, comme dans le SDK
   (`BRLMCustomPaperSize`):

   | Type | Réglages | Appel SDK |
   |---|---|---|
   | Continu | largeur | `rollWithTapeWidth` |
   | Prédécoupé | largeur, longueur d'étiquette, espace entre étiquettes | `dieCutWithTapeWidth` |
   | Marque noire | largeur, longueur d'étiquette, position et hauteur de la marque | `markRollWithTapeWidth` |

   La marque noire est imprimée au dos du rouleau; sa position se mesure
   depuis le début de l'étiquette. Valeurs de départ: position 0 mm,
   hauteur 3 mm, à ajuster selon le rouleau.

   Changer de modèle remet un papier compatible si l'ancien ne l'est plus.
3. **Coupe et copies** (Brother).

Ces choix sont conservés entre deux lancements (`UserDefaults`).

## Connexion

- **Bluetooth LE**: recherche des imprimantes Brother à proximité
  (`BRLMPrinterSearcher.startBLESearch`), puis connexion par leur nom local
  annoncé (`BRLMChannel(bleLocalName:)`).
- **Wi-Fi**: recherche sur le réseau local, ou saisie de l'adresse IP.
- **Bluetooth Classic (MFi)** n'est pas géré: il exige l'autre framework
  (`BT_Net`), un Product Plan ID Brother pour l'App Store et la clé
  `UISupportedExternalAccessoryProtocols`.

Selon le manuel du SDK, **les TD-4410D, TD-4420DN et TD-4520DN n'ont pas de
BLE**. L'application ne le leur propose pas: le TD-4420DN et le TD-4520DN
passent par le Wi-Fi, le TD-4410D (USB seulement) n'est pas pilotable
depuis iOS et ne figure pas dans l'énumération du SDK iOS.

Quand l'imprimante trouvée annonce un autre modèle que celui choisi,
l'application le signale et propose de basculer sur le modèle détecté.

« Tester la connexion et lire l'état » ouvre le canal, lit l'état
(papier, capot, batterie) et referme, sans imprimer.

## Coupe automatique

Le SDK expose sur `BRLMTDPrintSettings` (et `BRLMQLPrintSettings`):

| Réglage SDK | Option dans l'application | Effet d'après la documentation Brother |
|---|---|---|
| `autoCut` | Coupe automatique | coupe après chaque page |
| `autoCutForEachPageCount` | Couper toutes les N étiquettes | coupe toutes les N pages (1 par défaut), seulement si `autoCut` |
| `cutAtEnd` | Couper en fin d'impression | coupe après la dernière page du travail |

Sur une impression d'une seule étiquette, `autoCut` et `cutAtEnd` coupent au
même endroit. Ils se distinguent avec plusieurs copies: coupe automatique
toutes les 3 = paquets de trois; coupe en fin seule = une seule coupe à la
fin de la bande.

Les deux options sont **désactivées par défaut**: sur la TD-4550DNWB, le
massicot est un accessoire. Sans massicot installé, activer la coupe ne
coupe rien; si l'imprimante répond « équipement optionnel incompatible »,
l'application le dit et suggère de désactiver la coupe.

Les séries RJ, PJ et MW n'ont pas de coupe pilotable par le SDK: l'option
n'est pas affichée. Sur les PT, seule la coupe automatique existe, et
certaines P-touch n'ont qu'une coupe manuelle.

## Ajouter le SDK dans Xcode

1. Télécharger le Brother Print SDK for iPhone/iPad (4.13.2 ou plus récent)
   et décompresser `bpsdki4132.zip`.
2. Copier **`libs/Net/BRLMPrinterKit.xcframework`** dans
   `swift/Examples/DemoAppIOS/Vendor/` (dossier ignoré par git).
   `Net` suffit pour le BLE et le Wi-Fi et ne demande ni Product Plan ID
   ni accessoire externe. Ne prendre `libs/BT_Net` que pour le Bluetooth
   Classic MFi.
3. Ouvrir `PocketPrinter5890IOS.xcodeproj`, glisser le `.xcframework` dans
   le projet (cible `PocketPrinter5890IOS`), puis dans
   **General > Frameworks, Libraries, and Embedded Content**, choisir
   **Embed & Sign**.
4. Avec le framework `Net`, la documentation Brother demande d'ajouter
   `WLAN_ONLY` dans **Build Settings > Preprocessor Macros**.
5. Compiler. Le code Brother est protégé par `#if canImport(BRLMPrinterKit)`:
   il s'active dès que le framework est lié, sans autre modification.

Les clés `Info.plist` nécessaires sont déjà présentes:
`NSBluetoothAlwaysUsageDescription` pour le BLE, `NSLocalNetworkUsageDescription`
et `NSBonjourServices` (`_pdl-datastream._tcp`, `_printer._tcp`, `_ipp._tcp`)
pour le Wi-Fi. Le framework vise iOS 14 au minimum; l'application vise iOS 15.

Le simulateur n'a pas de Bluetooth: tester le BLE sur un iPhone réel.

## Fonctionnement de l'impression

Une Brother reçoit une image, pas de l'ESC/POS. Ticket, texte, codes,
démonstrations et mire sont dessinés avec la même mise en page que pour la
5890 (32 colonnes), directement à la résolution de la tête (`xdpi` donné
par `BRLMPrinterModelSpec`), puis envoyés par `printImage(with:settings:)`
avec mise à l'échelle sur la largeur du papier. Le rendu et l'envoi se font
hors du fil principal.

Avant l'envoi, les réglages passent par `BRLMValidatePrintSettings`: une
incohérence (papier trop large pour le modèle, par exemple) est affichée
au lieu d'être envoyée.

## Points à vérifier sur l'imprimante réelle

Cette intégration a été écrite d'après les en-têtes et la documentation du
SDK 4.13.2 et l'application d'exemple Swift de Brother. Elle n'a pas encore
été essayée sur une TD-4550DNWB.

- Bluetooth activé sur l'imprimante, et imprimante non connectée à un autre
  téléphone pendant la recherche.
- La recherche BLE renvoie bien « Brother TD-4550DNWB » et un nom local.
- Le papier choisi correspond au rouleau chargé, et l'imprimante a été
  calibrée pour ce papier (capteur d'espace pour le prédécoupé, capteur
  de marque pour la marque noire).
- Rouleau à marque noire: l'impression démarre au bon endroit de chaque
  étiquette; sinon, ajuster la position de la marque.
- Massicot installé: coupe automatique, coupe toutes les N et coupe en fin
  se comportent comme décrit, avec 1 puis plusieurs copies.
- Massicot absent: coupe activée, noter la réponse de l'imprimante (aucune
  coupe, ou erreur d'équipement optionnel).
- Netteté du texte et position horizontale sur rouleau 102 mm et sur
  étiquette 102×152 mm; ajuster les marges si besoin.
- Messages affichés pour capot ouvert, papier épuisé et imprimante éteinte.
