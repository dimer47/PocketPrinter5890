# PocketPrinter5890

Drive the thermal pocket printers sold by Lidl under the **Tronic**,
**SILVERCREST** and **Parkside** brands over Bluetooth Low Energy — without
the official app, and without any cloud service.

The protocol was established by reverse engineering: BLE traffic analysis on
real hardware, then decompilation of the official `com.printer.lidloffice`
Android application, which embeds the LuckPrinter SDK.

| TRONIC | SILVERCREST |
|---|---|
| ![TRONIC pocket printer](docs/images/tronic-1.jpg) | ![SILVERCREST pocket printer](docs/images/silvercrest-1.jpg) |

Both brands ship the same hardware, the same firmware and the same official
application: only the logo on the lid differs.

## What is here

| Directory | Contents |
|---|---|
| **[`docs/`](docs/)** | Protocol specification — the reference, independent of any language |
| **[`swift/`](swift/)** | Swift library for macOS, iOS and iPadOS, plus two demo apps |
| **[`web/`](web/)** | TypeScript library for the browser and Capacitor |

The protocol specification is the source of truth. Both implementations
follow it; if they ever disagree, the specification is what a third one
should be written against.

## Start here

**Reimplementing in another language?** Read
**[`docs/PROTOCOL_SPEC.md`](docs/PROTOCOL_SPEC.md)**. It is written to be
sufficient on its own: byte sequences, the flow-control algorithm, a
symptom-to-cause table and a minimal pseudocode implementation. No Swift or
TypeScript knowledge needed.

**Building an Apple app?** See [`swift/README.md`](swift/README.md).

**Building for the web or with Capacitor?** See [`web/README.md`](web/README.md).

## The hardware

```text
TRONIC
IAN 508705_2507
Article Name : Mini Pocket Printer
Model        : 5890
Battery      : 18500 Lithium Battery 3.7V 1200mAh 4.44Wh
Input        : USB-C; 5V = 1A
Manufactured : 09-2025
```

Reported by the device over BLE: model `A2Y`, firmware `V1.06LY`, advertised
as `Mini Pocket Printer_BLE`.

Print width is **384 dots** (48 bytes per line) at 203 dpi, on roughly 56 mm
continuous paper.

> **This is not a DP-L13.** The widely available documentation for the L13
> describes a 14 mm label printer with a 96-dot raster — a different machine.
> Applying its specifications here prevents printing entirely.

## The three things that block a naive implementation

Each of these cost significant time to find. They are the reason this
repository exists rather than a shorter gist.

**1. An activation sequence is mandatory.** Without `10 FF F1 03` followed by
twelve zero bytes as a *separate* write, the printer acknowledges every
command and executes nothing — not even a paper feed.

**2. `01 nn` frames are flow-control credits, not status.** The printer
announces how many packets it can accept. Pacing with a fixed delay instead
divides throughput by roughly twenty. Reading one as a reply makes `01 01`
look like "battery: 1%".

**3. The raster must be sent in bands.** A single large `GS v 0` command is
dropped. Split into bands of about 24 lines.

## What the firmware does not support

Established by printing on paper, not inferred:

| Command | Behaviour |
|---|---|
| `ESC t` — code page | Ignored. Nine pages tested, nine identical unreadable lines. |
| Non-ASCII characters | Solid block. Transliterate to ASCII. |
| `GS B` — reverse video | No effect. |
| `GS ( k` — QR code | Prints as literal text: `k1A2k1Ck1E1k1P0...` |
| `GS k` — barcode | Prints as literal text: `<I{BMETEO2026` |

Codes therefore have to be rasterised. The vendor app does the same: its SDK
exposes no text or code printing at all, only bitmaps.

## Status

| | Swift | TypeScript |
|---|---|---|
| Protocol, raster, ESC/POS | ✅ | ✅ |
| Barcodes (Code 128/39, EAN-13/8) | ✅ | ✅ |
| QR codes | ✅ CoreImage | ⚠️ bring your own encoder |
| Receipt rendering | ✅ CoreGraphics | ✅ Canvas |
| Printing verified on hardware | ✅ macOS + iPhone | ⏳ not yet |

Roughly twenty commands were transcribed from the vendor SDK but never
executed on this firmware; they are flagged as such in both implementations
and in the specification.

Firmware update was deliberately left unimplemented: an untested port failing
mid-write would leave the printer unusable.

## Contributing

This documents a single unit — `A2Y` / `V1.06LY`. Other brand variants or
firmware revisions may behave differently. Useful reports, in order of
interest:

1. An untested command actually run on hardware — state model, firmware,
   command and outcome.
2. A different model answering something else to `10 FF 20 F0`.
3. The compressed raster format: the SDK calls `setCompress(true)` for the
   A2Y, implying an encoding not documented here.
4. USB-C behaviour — does the printer stay awake while powered?

Corrections to any claim in the specification are welcome. Several early
diagnoses in this project turned out to be wrong, and are recorded as such.

## Licence

MIT.

Reverse engineering for interoperability, on legally acquired hardware. No
vendor code is redistributed: only protocol byte sequences — facts about a
wire format — have been documented and reimplemented.
