# Contributing

This repository documents **one** printer: model `A2Y`, firmware `V1.06LY`,
sold by Lidl as Tronic and SILVERCREST. Other brand variants or firmware
revisions may behave differently, and finding out is the most useful thing
anyone can contribute.

## Most useful reports

**1. An untested command, actually run.** About twenty commands were
transcribed from the vendor SDK but never executed on hardware. They are
listed in [`docs/PROTOCOL_SPEC.md`](docs/PROTOCOL_SPEC.md) section 9.2.

If you try one, please report:

- the model and firmware your printer reports (`10 FF 20 F0`, `10 FF 20 F1`);
- the exact bytes you sent;
- what happened — including "nothing", which is a result.

**2. A different printer.** If `10 FF 20 F0` answers something other than
`A2Y`, that alone is worth an issue: it tells us which parts of this document
are general and which are specific.

**3. Corrections.** Several diagnoses in this project turned out to be wrong
and were rewritten. If something here does not match what your hardware does,
the document is probably at fault. Say so.

## Open questions

Listed at the end of the specification. The compressed raster format is the
most interesting: the SDK calls `setCompress(true)` for the A2Y, implying an
encoding nobody has described yet.

## Code

Two implementations, both following the specification:

```bash
# Swift — macOS, iOS, iPadOS
cd swift && swift test

# TypeScript — browser, Capacitor
cd web && npm install && npm run build
```

If a change affects the protocol rather than one language, update
`docs/PROTOCOL_SPEC.md` too: it is the reference the implementations follow,
not the other way round.

## What not to do

Please do not add a firmware update path. `updatePrinterLuck` exists in the
vendor SDK and was deliberately left unimplemented: an untested port failing
mid-write leaves the printer unusable, and the payoff does not justify that.

## Reporting hardware behaviour

Claims about what the printer does should come from an actual print, not from
reading code. Several confident-looking deductions in this project were
wrong until paper contradicted them — a photograph of the output settles
arguments that source code cannot.
