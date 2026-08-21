# PocketPrinter5890 — Android

Kotlin library for the Lidl pocket thermal printers (Tronic, SILVERCREST,
Parkside), sold as the generic 5890 family.

Same protocol, same API shape and same method names as the Swift library in
[`../swift`](../swift). Anything you can do on iOS you can do here, spelled the
same way.

[Version française](README_FR.md) · [Protocol specification](../docs/PROTOCOL_SPEC.md)

## Modules

| Module | Contents |
|---|---|
| `kit` | Protocol, raster encoding, ESC/POS, documents, barcodes, QR. Pure JVM — no Android SDK, so tests run on your machine without an emulator. |
| `ble` | Ready-to-use BLE transport, including the credit-based flow control. |
| `demo` | Compose demo app: connection, receipt, tools, settings, console. |

## Requirements

- Android 7.0 (API 24) or later
- JDK 17 or later to build

## Quick start

```kotlin
val transport = PocketPrinterBleTransport(context)
transport.startScan()
// …once a device is picked:
transport.connect(device.address)

val printer = PocketPrinter(transport)
printer.setDensity(PrintDensity.STRONG)

val document = PrintDocument()
document.append(PrintElement.title("BAKERY"))
document.append(PrintElement.Separator())
document.append(PrintElement.Text("Baguette          1.20 EUR"))
document.append(PrintElement.Image(CodeBitmaps.qrCode("https://example.com")))
document.append(PrintElement.Feed(2))
printer.print(document)
```

`PocketPrinter` talks to a `PrinterTransport`. `PocketPrinterBleTransport`
implements it, but so can anything else — USB, a file, a test double.

## Permissions

The `ble` module declares what it needs, but Android 12+ requires the user to
grant them at runtime. Request `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` before
scanning; on Android 11 and below, request `ACCESS_FINE_LOCATION` and
`ACCESS_COARSE_LOCATION` together. Without them the scan returns no devices and
reports no error — see `MainActivity` in the demo.

## The three things that block a naive implementation

All three are in the protocol spec, and all three are handled for you here.

1. **Flow control by credits.** The `01 nn` frames on `FF03` are not
   acknowledgements — they say the printer can accept `nn` more packets.
   Pacing with a fixed delay instead divides throughput by roughly twenty.
2. **The activation sequence.** Without `10 FF F1 03` followed by twelve zero
   bytes as a *separate* write, the printer acknowledges everything and does
   nothing.
3. **Banded raster.** A raster sent as one large command is dropped. It must be
   split into bands of about 24 lines.

## What the firmware does not support

Verified on paper, not inferred: native QR and barcode commands print as
literal text, accented characters print as solid blocks, and `ESC t` code page
selection is ignored. The library works around all three — codes are
rasterised, text is transliterated to ASCII.

## Building

```bash
./gradlew build          # everything, including lint
./gradlew :kit:test      # protocol tests, no device needed
./gradlew :demo:assembleDebug
```

## Status

The protocol layer is covered by tests ported from the Swift suite and passing.
The BLE transport and the demo app compile and lint clean, but **have not yet
been run against a physical printer** — the hardware verification behind this
repository was done on macOS and iOS. Reports from an Android device are
welcome: [`TEST_MATERIEL.md`](TEST_MATERIEL.md) is a step-by-step procedure
(in French) for testing against real hardware.

Commands transcribed from the vendor SDK but never executed are marked as such
in the source, exactly as in the Swift library.
