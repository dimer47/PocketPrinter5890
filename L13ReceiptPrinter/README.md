# L13ReceiptPrinter

Librairie Swift et application macOS 13+ SwiftUI pour piloter en BLE une mini imprimante
thermique de poche SilverCrest / Tronic (Lidl), IAN 508705, famille generique 5890.

Papier thermique continu type ticket de caisse, largeur ~56 mm, 203 dpi.
**Largeur d'impression: 384 pixels, soit 48 octets par ligne.**

> Note historique: ce projet visait initialement une imprimante d'etiquettes L13 de 14 mm
> (96 px). Ce modele est different de celui utilise ici. La largeur 96 px reste disponible
> en option de compatibilite mais ne doit pas etre le defaut.

## Architecture

- `L13Core`: librairie d'impression reutilisable et independante du transport.
  - `ESCPOS`: jeu de commandes standard (texte, gras, alignement, taille, codes-barres, QR).
  - `PrintDocument` / `PrintElement`: description de haut niveau d'un document.
  - `RasterEncoder`: encodage 1 bit MSB-first et decoupage en bandes.
  - `MonochromeConverter`: seuil, tramage ordonne, Floyd-Steinberg.
  - `ReceiptRenderer`: rendu AppKit d'un ticket ou d'une image quelconque.
  - `PrintJobBuilder`: assemblage du flux d'octets final.
- `L13BLETransport`: scan CoreBluetooth, connexion, GATT, profils UART, notifications,
  file d'ecriture avec fragmentation MTU et reprise.
- `L13ReceiptPrinter`: application SwiftUI.
- `L13BLEProbe`: outil console de diagnostic.

## Portage du SDK officiel

`LuckPrinterCommands.swift` porte en Swift le jeu de commandes du LuckPrinter SDK,
extrait de l'application officielle `com.printer.lidloffice`. `PocketPrinter` en est
la facade de haut niveau, equivalente a l'objet `Printer` du SDK Java.

```swift
let printer = PocketPrinter(transport: bleTransport)
printer.readDeviceInformation()      // modele, firmware, batterie, papier
printer.setDensity(.strong)
printer.setAutoShutdown(minutes: 30)
printer.print(text: "BONJOUR")
printer.feed(dots: 80)
```

Commandes verifiees sur le materiel: activation, reveil, arret de travail, calage,
avance, densite, modele, firmware, batterie, statut. Les autres (vitesse, chauffe,
horloge, marques de decoupe, mode, reglages d'usine) sont portees fidelement mais
non testees sur ce firmware; elles sont signalees « non verifiee » dans le code.

## Utiliser la librairie

```swift
import L13Core

var document = PrintDocument()
document.append(.title("BOULANGERIE"))
document.append(.centered("12 rue des Lilas"))
document.append(.separator(character: "-"))
document.append(.text("2x Baguette", alignment: .left))
document.append(.text("TOTAL  2,40 EUR", size: 2, bold: true, alignment: .right))
// Codes en image: le firmware A2Y n'interprete pas les commandes natives
// `GS ( k` / `GS k`, il les imprimerait en clair.
document.append(try PrintElement.qrCodeImage("https://exemple.fr"))
document.append(try PrintElement.barcodeImage("REF12345"))
document.append(.feed(lines: 3))

let bytes = PrintJobBuilder.bytes(document: document, options: PrintOptions())
// `bytes` est ensuite envoye au transport de votre choix.
```

Imprimer une image:

```swift
let renderer = ReceiptRenderer(width: 384, ditherMode: .floydSteinberg)
let bitmap = try renderer.bitmap(from: monImage)
let bytes = PrintJobBuilder.bytes(
    document: PrintDocument(elements: [.image(bitmap)]),
    options: PrintOptions()
)
```

## Texte natif: limites du firmware

Une mire testant les neuf pages de code ESC/POS (`ESC t 0` a `ESC t 19`) a
produit **neuf lignes identiques, toutes illisibles**: le firmware ignore
`ESC t` et ne connait que l'ASCII en mode texte. Il laisse meme un octet
parasite s'imprimer apres la commande.

Consequences, appliquees par defaut:

- `ESC t` n'est jamais envoye;
- le texte est translitere en ASCII (`18°C` devient `18degC`, `café` devient
  `cafe`, `12 €` devient `12 EUR`) via `ESCPOS.transliterate(_:)`;
- les lignes sont decoupees sur les espaces a 32 colonnes, sinon le firmware
  coupe au caractere pres (« l'apres-midi. » devenait « l'apres-m » / « idi. »).

L'inversion video `GS B` n'est pas non plus implementee.

Pour un rendu typographique complet (accents, symboles, polices, inversion),
passer par le mode image: c'est ce que fait l'application officielle, dont le
SDK n'expose **aucune** fonction d'impression de texte, uniquement des bitmaps.

`PrintOptions.transliterateText` permet de desactiver la transliteration.

## Codes-barres et QR codes

Le firmware A2Y **n'implemente pas** les commandes ESC/POS natives `GS ( k`
(QR) et `GS k` (code-barres): elles sont imprimees en clair, par exemple
`k1A2k1Ck1E1k1P0https://...`. L'application officielle ne les utilise pas non
plus; elle genere les codes en image puis les imprime en raster.

```swift
document.append(try PrintElement.qr("https://exemple.fr"))
document.append(try PrintElement.code("REF12345", symbology: .ean13))
```

Symbologies disponibles: Code 128, Code 39, EAN-13, EAN-8. La cle de controle
EAN est calculee si elle est omise, et verifiee si elle est fournie.

Les codes-barres lineaires sont generes en **Swift pur** (`Barcode1D`), sans
aucune dependance systeme: la librairie reste portable. Les QR codes
s'appuient sur CoreImage, isole derriere `CodeBitmaps.qrMatrix` pour pouvoir
etre remplace sans toucher au reste du code.

Dans tous les cas les modules sont ecrits directement dans le bitmap, sans
interpolation ni tramage: un code adouci ou trame devient illisible au
scanner. Les QR produits ont ete verifies par decodage automatique, pas
seulement a l'oeil.

## Etat de l'imprimante

Le transport publie en continu:

```swift
transport.batteryPercent   // Int?, rafraichi toutes les 25 s
transport.deviceModel      // "A2Y"
transport.deviceFirmware   // "V1.06LY"
```

La batterie est lue via `10 FF 50 F1`; le pourcentage se trouve dans le
deuxieme octet de la reponse (`02 64 00` = 100 %). La periode de 25 secondes
reprend celle du `BatteryLoader` de l'application officielle. La lecture est
suspendue tant qu'un travail d'impression est en file, pour ne pas s'inserer
au milieu d'un raster.

## Modes papier

- **Papier continu**: aucune longueur declaree, l'impression s'arrete a la fin du
  contenu. Une avance de degagement (80 points par defaut, ~10 mm) sort le ticket
  de sous la tete d'impression.
- **Etiquettes**: longueur declaree via `1F 80`, avec calage `1D 0C` entre chaque
  etiquette. L'imprimante deroule jusqu'a la fin de l'etiquette declaree.

Le SDK officiel distingue ces deux cas par `printOnce()` et `printTagOnce()`:
envoyer `1F 80` sur du papier continu fait derouler du papier inutilement.

## Protocole

Raster ESC/POS, envoye par bandes de 24 lignes:

```text
1D 76 30 00 30 00 <yL> <yH> <pixels>
         |  |  |
         |  +--+-- 48 octets par ligne = 384 px
         +-------- mode normal
```

Sequence d'un travail:

```text
1B 40              init
1B 74 10           page de code Latin-1
10 FF 10 00 01     densite moyenne
1D 76 30 ...       bandes raster
1B 64 03           avance finale
```

Commandes proprietaires utiles: `10 FF 40` etat papier, `10 FF 50 F1` batterie,
`10 FF 10 00 n` densite. Elles repondent `OK` sur la caracteristique FF01.

## BLE

Le service qui repond est `FF00`: ecriture sur `FF02`, notifications sur `FF01` et `FF03`.
Profils de repli: Microchip Transparent UART, `18F0`, `e781...`.

## Permissions macOS

`Sources/L13ReceiptPrinter/BluetoothInfoTemplate.plist` porte `NSBluetoothAlwaysUsageDescription`
et `L13ReceiptPrinter.entitlements` l'entitlement Bluetooth sandbox. Pour une distribution
signee, recopier ces reglages dans la cible Xcode archivee.

## Essai avec l'imprimante

1. Charger l'imprimante et inserer le papier.
2. Ouvrir `L13ReceiptPrinterApp.xcodeproj`, schema `L13ReceiptPrinterApp`, lancer sur `My Mac`.
3. `Rechercher`, choisir `Mini Pocket Printer_BLE`, connecter.
4. Verifier que la largeur selectionnee est `58 mm - 384 px`.
5. Imprimer la mire: le cadre doit occuper toute la largeur du papier et le libelle
   afficher `384 px`. Une large marge blanche a droite signale une largeur trop faible.
6. Imprimer le ticket.

Le statut `01 04` remonte par le capteur est informatif et n'empeche pas d'imprimer.

## Tests

```bash
swift test
xcodebuild -project L13ReceiptPrinterApp.xcodeproj -scheme L13ReceiptPrinterApp -destination 'platform=macOS' build
```

L'impression physique n'a pas encore ete confirmee par un essai reel avec ce code.
