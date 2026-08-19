# PocketPrinter5890 — TypeScript

*[English version](README.md) · [Racine du projet](../README_FR.md)*

Piloter la mini imprimante thermique Lidl Tronic/SILVERCREST 5890 depuis un
navigateur ou depuis Capacitor.

Reference du protocole:
[`../docs/PROTOCOL_SPEC.md`](../docs/PROTOCOL_SPEC.md).

## Installation

```bash
npm install pocketprinter5890
```

## Navigateur (Chrome, Edge, Opera)

```ts
import { PocketPrinter, WebBluetoothTransport, PrintDocument } from 'pocketprinter5890';

const printer = new PocketPrinter(new WebBluetoothTransport());

// Doit partir d'un geste utilisateur: le navigateur en exige un pour
// ouvrir le selecteur de peripherique.
bouton.addEventListener('click', async () => {
  await printer.connect();
  await printer.readDeviceInformation();

  const ticket = new PrintDocument()
    .title('BOULANGERIE')
    .centered('12 rue des Lilas')
    .separator()
    .text('2x Baguette                 2,40')
    .feed(1);

  await printer.print(ticket);
});
```

**Web Bluetooth n'existe ni sur Firefox ni sur Safari** — les deux editeurs
ont refuse de l'implementer. Utiliser le transport Capacitor sur ces
plateformes.

## Capacitor (iOS, Android)

Le plugin est injecte plutot que declare en dependance, pour que le paquet
reste utilisable dans un navigateur seul.

```bash
npm install @capacitor-community/bluetooth-le
```

```ts
import { BleClient } from '@capacitor-community/bluetooth-le';
import { PocketPrinter, CapacitorTransport } from 'pocketprinter5890';

const printer = new PocketPrinter(new CapacitorTransport(BleClient));
await printer.connect();
```

> L'adaptateur Capacitor est ecrit d'apres la documentation du plugin mais
> n'a pas ete execute sur un appareil.

## Impression d'images

```ts
import { bitmapFromCanvas, DitherMode } from 'pocketprinter5890';

const bitmap = bitmapFromCanvas(monCanvas, { dither: DitherMode.FloydSteinberg });
await printer.printBitmap(bitmap);
```

Tout ce qui se dessine sur un canvas s'imprime: texte dans n'importe quelle
police, accents, logos. C'est ainsi que procede l'application officielle, et
cela contourne le mode texte de l'imprimante, limite a l'ASCII.

## Tickets

```ts
import { renderReceipt, sampleReceipt } from 'pocketprinter5890';

const bitmap = renderReceipt({ ...sampleReceipt, merchantName: 'BOULANGERIE' });
await printer.printBitmap(bitmap);
```

Les tickets sont dessines sur un canvas et imprimes en image, ce qui evite
la police ASCII du firmware: accents et symboles sortent correctement.

## Codes-barres

Code 128, Code 39, EAN-13 et EAN-8 sont generes en TypeScript pur, sans
aucune dependance:

```ts
import { renderBarcode, Symbology } from 'pocketprinter5890';

const bitmap = renderBarcode('5901234123457', Symbology.EAN13, { height: 80 });
await printer.printBitmap(bitmap);
```

La cle de controle EAN est calculee si elle est omise, et verifiee si elle
est fournie.

## QR codes

Cette librairie ne fournit volontairement **pas** d'encodeur QR: en ecrire un
correct est une source d'erreurs silencieuses, un code invalide restant
indiscernable a l'oeil tout en echouant a chaque scan. Passer plutot la
matrice d'une bibliotheque eprouvee.

```bash
npm install qrcode-generator
```

```ts
import qrcode from 'qrcode-generator';
import { renderQR } from 'pocketprinter5890';

const qr = qrcode(0, 'M');
qr.addData('https://exemple.fr');
qr.make();

const bitmap = renderQR({
  size: qr.getModuleCount(),
  isDark: (x, y) => qr.isDark(y, x),
});
await printer.printBitmap(bitmap);
```

La commande QR native de l'imprimante n'est pas implementee par le firmware:
elle s'imprime en clair. La rasterisation est la seule voie.

## Controle de flux

Gere automatiquement. L'imprimante emet des trames `01 nn` annoncant combien
de paquets elle peut accepter; la librairie attend un credit avant d'envoyer
du volume. L'ignorer divise le debit par vingt environ.

La logique vit dans la couche protocole et non dans les adaptateurs de
transport: elle est donc ecrite une seule fois, quelle que soit la
plateforme.

```ts
printer.useFlowControl = false;  // uniquement pour comparer
```

## Transport personnalise

Implementer `Transport` pour couvrir une autre plateforme:

```ts
import type { Transport } from 'pocketprinter5890';

class MonTransport implements Transport {
  isConnected = false;
  maxChunkSize = 180;
  async connect() { /* ... */ }
  async disconnect() { /* ... */ }
  async write(bytes: Uint8Array) { /* ... */ }
  onNotification(handler: (bytes: Uint8Array) => void) { /* ... */ }
  onDisconnect(handler: () => void) { /* ... */ }
}
```

Le controle de flux, le decoupage en paquets et la sequence d'activation sont
geres au-dessus de cette couche.

## Demonstration

`demo/index.html` est une page autonome pour Chrome, au niveau de ce
qu'offrent les applications macOS et iOS: connexion avec batterie et
firmware, editeur de ticket avec apercu, texte natif, codes-barres, QR
codes, images, documents de demonstration, reglages machine et console
hexadecimale.

```bash
npm run build
npx serve .        # Web Bluetooth exige https ou localhost
```

## Compilation

```bash
npm install
npm run build
```

## Etat

Protocole, encodage raster, ESC/POS, codes-barres, rendu de ticket, rendu
Canvas et les deux transports sont implementes, et la sortie octet a ete
comparee a l'implementation Swift de reference.

L'impression a ete verifiee depuis Chrome sur materiel: texte, codes-barres
et images. L'adaptateur Capacitor n'a pas ete execute sur appareil.

Deux fonctions restent hors de portee du navigateur, quelle que soit
l'implementation: lister les peripheriques proches avec leur puissance de
signal, et choisir un service BLE alternatif. L'API Web Bluetooth impose son
propre selecteur et n'expose ni l'un ni l'autre.
