# PocketPrinter5890 — TypeScript

*[Version française](README_FR.md) · [Project root](../README.md)*

Drive the Lidl Tronic/SILVERCREST 5890 thermal pocket printer from the
browser or from Capacitor.

Protocol reference: [`../docs/PROTOCOL_SPEC.md`](../docs/PROTOCOL_SPEC.md).

## Install

```bash
npm install pocketprinter5890
```

## Browser (Chrome, Edge, Opera)

```ts
import { PocketPrinter, WebBluetoothTransport, PrintDocument } from 'pocketprinter5890';

const printer = new PocketPrinter(new WebBluetoothTransport());

// Must be called from a user gesture: the browser requires one to open
// the device chooser.
button.addEventListener('click', async () => {
  await printer.connect();
  await printer.readDeviceInformation();

  const receipt = new PrintDocument()
    .title('BAKERY')
    .centered('12 Lilac Street')
    .separator()
    .text('2x Baguette                 2.40')
    .feed(1);

  await printer.print(receipt);
});
```

**Web Bluetooth is unavailable in Firefox and Safari** — both vendors
declined to implement it. Use the Capacitor transport there.

## Capacitor (iOS, Android)

The plugin is injected rather than depended on, so the package stays usable
in a plain browser.

```bash
npm install @capacitor-community/bluetooth-le
```

```ts
import { BleClient } from '@capacitor-community/bluetooth-le';
import { PocketPrinter, CapacitorTransport } from 'pocketprinter5890';

const printer = new PocketPrinter(new CapacitorTransport(BleClient));
await printer.connect();
```

> The Capacitor adapter is written against the plugin's documented API but has
> not been run on a device.

## Printing images

```ts
import { bitmapFromCanvas, DitherMode } from 'pocketprinter5890';

const bitmap = bitmapFromCanvas(myCanvas, { dither: DitherMode.FloydSteinberg });
await printer.printBitmap(bitmap);
```

Anything you can draw on a canvas can be printed: text in any font, accents,
logos. This is how the vendor app works, and it sidesteps the firmware's
ASCII-only text mode.

## Barcodes

Code 128, Code 39, EAN-13 and EAN-8 are generated in pure TypeScript, with no
dependency:

```ts
import { renderBarcode, Symbology } from 'pocketprinter5890';

const bitmap = renderBarcode('5901234123457', Symbology.EAN13, { height: 80 });
await printer.printBitmap(bitmap);
```

The EAN check digit is computed when omitted and verified when supplied.

## QR codes

This library does **not** include a QR encoder, deliberately: writing a
correct one is error-prone, and a wrong QR code looks fine to the eye while
failing every scanner. Pass a matrix from a proven library instead.

```bash
npm install qrcode-generator
```

```ts
import qrcode from 'qrcode-generator';
import { renderQR } from 'pocketprinter5890';

const qr = qrcode(0, 'M');
qr.addData('https://example.com');
qr.make();

const bitmap = renderQR({
  size: qr.getModuleCount(),
  isDark: (x, y) => qr.isDark(y, x),
});
await printer.printBitmap(bitmap);
```

Note that the printer's native QR command is not implemented by the firmware:
it prints the command as literal text. Rasterising is the only route.

## Flow control

Handled automatically. The printer emits `01 nn` credit frames announcing how
many packets it can accept; the library waits for credit before sending bulk
data. Ignoring this divides throughput by roughly twenty.

The logic lives in the protocol layer rather than in transport adapters, so
it is written once regardless of platform.

```ts
printer.useFlowControl = false;  // only to compare behaviour
```

## Custom transport

Implement `Transport` to support another platform:

```ts
import type { Transport } from 'pocketprinter5890';

class MyTransport implements Transport {
  isConnected = false;
  maxChunkSize = 180;
  async connect() { /* ... */ }
  async disconnect() { /* ... */ }
  async write(bytes: Uint8Array) { /* ... */ }
  onNotification(handler: (bytes: Uint8Array) => void) { /* ... */ }
}
```

Flow control, chunking and the activation sequence are handled above this
layer.

## Receipts

```ts
import { renderReceipt, sampleReceipt } from 'pocketprinter5890';

const bitmap = renderReceipt({ ...sampleReceipt, merchantName: 'BAKERY' });
await printer.printBitmap(bitmap);
```

Receipts are drawn on a canvas and printed as an image, which sidesteps the
firmware's ASCII-only text mode: accents, symbols and any web font come out
correctly.

## Demo

`demo/index.html` is a self-contained page for Chrome, matching what the
macOS and iOS apps offer: connection with battery and firmware, receipt
editor with live preview, native text, barcodes, QR codes, images, demo
documents, printer settings and a hex console.

```bash
npm run build
npx serve .        # Web Bluetooth requires https or localhost
```

## Build

```bash
npm install
npm run build
```

## Status

Protocol, raster encoding, ESC/POS, barcodes, receipt rendering, canvas
rendering and both transports are implemented, and the byte output has been
checked against the Swift reference implementation.

Two things the browser cannot do, whatever the implementation: listing nearby
devices with their signal strength, and choosing an alternative BLE service.
The Web Bluetooth API imposes its own device chooser and exposes neither.

Printing has been verified from Chrome on real hardware: text, barcodes and
images all come out. The Capacitor adapter has not been run on a device.
