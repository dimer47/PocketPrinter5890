# Pocket Printer 5890 — protocol specification

Language-independent description of the printing protocol used by the thermal
pocket printers sold by Lidl under the **Tronic**, **SILVERCREST** and
**Parkside** brands.

This document is written so the protocol can be reimplemented from scratch,
in any language, without reading the Swift reference implementation. It
records what was observed on real hardware, and states plainly what was not.

| | |
|---|---|
| Reference device | Mini Pocket Printer, model 5890, IAN 508705_2507 |
| Reported model | `A2Y` |
| Reported firmware | `V1.06LY` |
| BLE advertised name | `Mini Pocket Printer_BLE` |
| Print width | 384 dots (48 bytes per line) |
| Resolution | 203 dpi |

Everything below was established on that single unit. Other brand variants or
firmware revisions may differ.

---

## 1. Transport

### 1.1 BLE service

The printer advertises four services. **Only `FF00` responds.**

| Role | UUID |
|---|---|
| Service | `0000FF00-0000-1000-8000-00805F9B34FB` |
| Write | `FF02` — write without response |
| Notify | `FF01` — solicited replies |
| Notify | `FF03` — status and flow control |

Subscribe to **both** `FF01` and `FF03`: they carry different traffic.

The other advertised services (`49535343-...` Microchip Transparent UART,
`18F0`, `e7810a71-...`) accept writes but never notify. Writing to them
appears to succeed and does nothing.

### 1.2 Other transports

The hardware also exposes USB-C. This document covers BLE only; the USB path
has not been investigated.

The protocol itself is transport-agnostic — the byte sequences below are the
same over any serial-like channel. Only sections 1.1 and 2 are BLE-specific.

### 1.3 Platform notes

The protocol is identical everywhere; only the way you obtain a byte channel
differs.

| Platform | Channel |
|---|---|
| macOS, iOS, iPadOS | CoreBluetooth. See the Swift implementation in this repository, verified on both macOS and a physical iPhone. |
| Chrome, Edge, Opera | Web Bluetooth. Requires a user gesture to open the device chooser: no silent reconnection. |
| Firefox, Safari | **Web Bluetooth unavailable.** Both vendors declined to implement it. Use a native wrapper. |
| iOS/Android from web code | Capacitor with a native BLE plugin. |

A web implementation covering both Chrome and Capacitor is practical: keep
one protocol module and give it two transport adapters, each exposing a
single `write(bytes)` method. Put the credit logic of section 2 **inside the
protocol module**, not in the adapters — otherwise it gets written twice and
one copy will be wrong.

Note that receipt rendering does not port: it relies on the host graphics
stack (CoreGraphics on Apple platforms, Canvas on the web). Only the raster
encoding of section 5 is shared.

---

## 2. Flow control — read this before writing any code

**This is the single most commonly missed part of the protocol.**

The printer emits two-byte frames on `FF03`:

```
01 nn
```

These are **not** acknowledgements, and **not** status codes. They are
**credits**: the printer is announcing it can accept `nn` more packets.

The reference algorithm, from the vendor SDK:

```
on notification(bytes):
    if length(bytes) == 2 and bytes[0] == 0x01:
        credits += bytes[1]

before writing a packet:
    wait until credits > 0
    write packet
    credits -= 1
```

Ignoring this and pacing writes with a fixed delay instead divides throughput
by roughly twenty — the difference between a receipt printing in two seconds
and in forty.

Two consequences that are easy to get wrong:

- A `01 nn` frame must **not** be treated as the reply to a pending command.
  Doing so makes `01 01` look like "battery: 1%" when the real reply
  (`00 62`, 98%) arrives immediately after.
- Short configuration commands can be sent without waiting for credit; only
  bulk raster data needs pacing.

Packet size: the vendor app negotiates an MTU up to 512 bytes. 180 bytes
works reliably. 20 bytes (the BLE minimum) works but is very slow.

**Reset the credit count on every connection.** Credits belong to one
session: carrying a stale count across a reconnection makes the printer look
like it still owes packets, and the next job stalls waiting for credit that
never arrives. Watch for the disconnection event too — switching the printer
off does not surface as an error on the write path, so an implementation that
ignores it will happily queue bytes into the void.

---

## 3. Mandatory activation sequence

**Without this, the printer acknowledges every command and executes
nothing** — not even a paper feed. This is the second most commonly missed
part of the protocol.

```
10 FF F1 03                     enable motor (mode 3)
00 00 00 00 00 00 00 00 00 00 00 00    wake-up — 12 zero bytes
```

The twelve zero bytes are a **separate write**, not padding appended to
`10 FF F1 03`. Several public write-ups state otherwise; sending them
concatenated does not work.

Every print job must end with:

```
10 FF F1 45                     stop print job
```

### 3.1 This applies to every command, not just printing

The activation sequence is not a "printing" concern. A bare `1B 4A 50` paper
feed, or a bare `10 FF 20 F0` model query, is acknowledged and ignored just
the same.

Wrap **any** command in the sequence:

```
10 FF F1 03
00 x12
<your command>
10 FF F1 45
```

This is easy to get wrong twice: an implementation can print perfectly while
its "read device info" and "feed paper" buttons silently do nothing.

---

## 4. Print job structure

Two modes, kept distinct in the vendor SDK (`printOnce` vs `printTagOnce`).

### 4.1 Continuous paper (receipt roll)

```
10 FF F1 03                     enable
00 x12                          wake-up
1B 40                           ESC/POS init            (optional)
10 FF 10 00 <density>           density                 (optional)
1D 76 30 00 30 00 <yL> <yH> <data>   raster band        (repeat)
1B 4A <n>                       clearance feed
10 FF F1 45                     stop
```

Do **not** send `1F 80` here. It declares a fixed label length and makes the
printer feed paper to the end of that declared length.

### 4.2 Labels

```
10 FF F1 03                     enable
00 x12                          wake-up
1F 80 <type> <length>           declare label — vendor app uses (01, 20)
...raster...
1B 4A <n>                       feed
1D 0C                           position next label
10 FF F1 45                     stop
```

### 4.3 Clearance feed

The print head sits recessed inside the case. Without a trailing feed the end
of the receipt stays hidden under the lid.

The SDK calls this `endLineDot` and sets it per model, from 50 to 144 dots.
80 dots (~10 mm at 203 dpi) is a reasonable default.

`1B 4A n` takes a single byte, so `n` maxes at 255 (~32 mm). For longer
feeds, repeat the command.

---

## 5. Raster format

```
1D 76 30 00 <xL> <xH> <yL> <yH> <data>
```

| Field | Value |
|---|---|
| `1D 76 30` | GS v 0 — ESC/POS raster |
| `00` | mode: normal |
| `xL xH` | bytes per line, little-endian. **`30 00` = 48 bytes = 384 dots** |
| `yL yH` | number of lines, little-endian |
| `data` | `xL*xH * yL*yH` bytes |

Pixel encoding: 1 bit per pixel, **MSB first**, a set bit prints a black dot.
The leftmost pixel of a line is bit 7 of the first byte.

### 5.1 Send in bands

**A raster sent as one large command is dropped.** Split the image into bands
of about 24 lines, each a complete `1D 76 30` command carrying its own height.

For a 384×240 image, that means 10 commands of 24 lines rather than one
command of 11 520 bytes.

### 5.2 Physical margins

The head covers 48 mm on roughly 56 mm of paper. About 8 mm of margin is
mechanical and cannot be removed in software. The split between left and
right margin depends on how the roll sits, so it varies between loads.

---

## 6. Text mode

The printer has an internal ESC/POS font. Note that the vendor app never uses
it — it renders all text to a bitmap on the phone. Text mode works, but it is
off the path the manufacturer took, and its limitations (section 8) reflect
that.

Working commands:

```
1B 40                init / reset formatting
1B 61 <n>            align: 0 left, 1 centre, 2 right
1B 45 <n>            bold: 0 off, 1 on
1B 2D <n>            underline: 0 none, 1 thin, 2 thick
1D 21 <n>            character size: high nibble width, low nibble height,
                     0 = 1x, 1 = 2x, up to 7 = 8x
1B 64 <n>            feed n lines
1B 4A <n>            feed n dots
0A                   line feed
```

Line width at size 1 is **32 characters**. Longer lines are cut mid-word by
the firmware, so wrap them yourself before sending.

At size 2 the usable width halves to 16 characters, and so on.

---

## 7. Proprietary commands

All verified against the vendor SDK. Verification status on hardware is given
in section 9.

### 7.1 Read

```
10 FF 20 F0          model                  -> "A2Y"
10 FF 20 F1          firmware               -> "V1.06LY"
10 FF 20 F2          serial number
10 FF 20 EF          bootloader version
10 FF 20 A0          print speed
10 FF 50 F1          battery                -> 00 nn, nn = percent
10 FF 40             paper status
10 FF 11             density
10 FF 13             auto power-off         -> two bytes, big-endian
10 FF B0             time format
10 FF 70             settings
```

Replies arrive on `FF01`, usually after a `01 nn` credit frame on `FF03`.

The battery percentage is the **second byte** of the reply, in both observed
forms (`02 64 00` emitted spontaneously, `00 62` in reply to a request).

### 7.2 Write

```
10 FF 10 00 <n>           density: 0 light, 1 medium, 2 dark
10 FF 12 <hi> <lo>        auto power-off, minutes — TWO bytes, BIG-endian
10 FF 15 <lo> <hi>        print width, dots — TWO bytes, LITTLE-endian
10 FF C0 <n>              print speed
10 FF 30 27 <n>           printer mode
10 FF 04                  factory reset — DESTRUCTIVE
10 FF 53 4A <f> + <date>  clock: header, then YYYY(2) MM DD hh mm ss
1F 70 01 <n>              heating level
1F 11 11 <n>              reverse feed
1F 11 <n>                 auto positioning
1B BB CC                  mark: first label
1B BB BB                  mark: last label
1B BB AA                  mark: intermediate label
FC FF 00 02 45 02 00 46   declare client platform
```

### 7.3 Byte-order warning

The SDK is **not consistent** between these two:

```
10 FF 12 <hi> <lo>        big-endian     (n/256, n%256)
10 FF 15 <lo> <hi>        little-endian  (n%256, n/256)
```

Getting either backwards produces a plausible-looking but wrong value.

The clock command needs its `10 FF 53 4A <f>` header; sending the seven date
bytes alone does nothing.

---

## 8. What this firmware does NOT support

Established by printing on paper, not inferred from code. Attempting these
wastes time and paper.

| Command | Behaviour |
|---|---|
| `1B 74 <n>` — code page | **Ignored.** Nine code pages tested, nine identical unreadable lines. Also leaks a stray byte into the output. |
| Non-ASCII characters | **Solid block.** `°`, `é`, `è`, `à`, `û`, `ç` all print as a filled square regardless of declared code page. |
| `1D 42 <n>` — reverse video | No visible effect. |
| `1D 28 6B ...` — QR code | **Printed as literal text.** Actual output: `k1A2k1Ck1E1k1P0https://...` |
| `1D 6B ...` — barcode | **Printed as literal text.** Actual output: `<I{BMETEO2026` |

### 8.1 Working around the character limitation

Transliterate to ASCII before sending: `18°C` becomes `18degC`, `café`
becomes `cafe`, `12 €` becomes `12 EUR`. A slightly approximate line beats an
unreadable one.

### 8.2 Working around the code limitation

Generate QR codes and barcodes as bitmaps and send them through `1D 76 30`.
This is what the vendor app does — it uses ZXing on the phone and never emits
a native code command.

When rasterising a code:

- use a **hard threshold**, never dithering — a dithered code will not scan;
- disable interpolation when scaling — soft edges break scanners;
- keep the 4-module quiet zone required by the QR standard.

---

## 9. Verification status

### 9.1 Verified on hardware

```
10 FF F1 03      activation
00 x12           wake-up
10 FF F1 45      stop job
1F 80 t l        paper type
1D 0C            positioning
1D 76 30 ...     raster
1B 4A n          dot feed
1B 64 n          line feed
1B 40            init
10 FF 10 00 n    density
10 FF 20 F0      model
10 FF 20 F1      firmware
10 FF 50 F1      battery
10 FF 40         paper status
1B 61 n          alignment
1B 45 n          bold
1D 21 n          character size
```

### 9.2 Transcribed from the SDK, NEVER EXECUTED

The SDK covers over 150 printer models. Nothing guarantees the A2Y implements
these. **Test before relying on them.**

```
10 FF C0 n           print speed
1F 70 01 n           heating level
10 FF 12 hi lo       auto power-off
10 FF 13             read auto power-off
10 FF 30 27 n        printer mode
10 FF 04             factory reset — DESTRUCTIVE if supported
10 FF 53 4A f + date clock
10 FF B0             read time format
10 FF 15 lo hi       print width
10 FF 20 F2          serial number
10 FF 20 EF          bootloader
10 FF 20 A0          read speed
10 FF 11             read density
10 FF 70             read settings
1B BB CC / BB / AA   cut marks
1F 11 11 n           reverse feed
1F 11 n              auto positioning
FC FF 00 02 45 02 00 46   platform declaration
```

Particular caution on `10 FF 12`: the value `0` is offered as "disable
power-off" by common convention. **This is unverified** — the firmware may
reject it or clamp to a minimum. Read back with `10 FF 13` to find out what
was actually stored.

### 9.3 Deliberately not implemented

Firmware update (`updatePrinterLuck` in the SDK, via `YXFirmwareUpdater`). An
untested implementation that fails mid-write leaves the printer unusable.

---

## 10. Symptoms and causes

Problems that look like hardware faults but are not.

| Symptom | Cause |
|---|---|
| Everything is acknowledged, nothing prints | Activation sequence missing (section 3) |
| Printing crawls, millimetre by millimetre | Flow-control credits ignored (section 2) |
| Raster truncated partway through | Sent as one block instead of bands (section 5.1) |
| Paper keeps feeding after the job | `1F 80` sent on continuous paper (section 4.1) |
| Line cut mid-word | Line longer than 32 characters (section 6) |
| Squares instead of accents | Firmware limitation (section 8) |
| QR code prints as gibberish text | Native QR command unsupported (section 8) |
| End of receipt stuck under the lid | No clearance feed (section 4.3) |
| Asymmetric side margins | Mechanical, not correctable (section 5.2) |
| Battery reads 1% | `01 01` credit frame mistaken for the reply (section 2) |
| Worked once, then everything stalls | Stale credits kept across a reconnection (section 2) |
| Still "connected" after switching the printer off | Disconnection event not handled (section 2) |

---

## 11. Minimal implementation

The shortest path to a working print, in pseudocode:

```
connect to service FF00
subscribe to FF01 and FF03
credits = 0

on notify(bytes):
    if len(bytes) == 2 and bytes[0] == 0x01:
        credits += bytes[1]

write(10 FF F1 03)                  # enable
write(00 x12)                       # wake-up
write(10 FF 10 00 01)               # medium density

for each band of 24 lines:
    header = 1D 76 30 00 30 00 <lines> 00
    for each 180-byte chunk of (header + band data):
        wait for credits > 0
        write(chunk)
        credits -= 1

write(1B 4A 50)                     # 80-dot clearance
write(10 FF F1 45)                  # stop
```

That is enough to print an image. Everything else is refinement.

---

## 12. Open questions

Contributions welcome on any of these.

- **Compressed raster.** The SDK calls `setCompress(true)` for model `A2Y`,
  implying a compressed encoding this document does not describe. The
  uncompressed path works; compression would speed up large jobs.
- **USB-C behaviour.** Does the printer stay awake while powered? Absent from
  both the SDK and the product documentation.
- **Third byte of the battery frame.** `02 64 **00**` — ignored by the SDK.
  The status bitfield has an `isCharging` bit (0x20), suggesting this byte
  might carry charge state, but this is unconfirmed.
- **Grayscale printing.** The SDK exposes `getRealGrayLevel`; the encoding is
  not documented here.
- **Other models.** This document describes one unit. Reports from other
  brand variants or firmware revisions would help establish what is general
  and what is specific.

---

## Provenance

Established by reverse engineering for interoperability, on legally acquired
hardware: BLE traffic analysis, then decompilation of the official
`com.printer.lidloffice` Android application, which embeds the LuckPrinter
SDK.

No vendor code is reproduced here. Only protocol byte sequences — which are
facts about a wire format, not authored expression — have been documented,
and every claim of hardware behaviour was checked by printing.
