/**
 * PocketPrinter5890 — drive the Lidl Tronic/SILVERCREST 5890 thermal pocket
 * printer over Bluetooth, from a browser or from Capacitor.
 *
 * Protocol documented in `docs/PROTOCOL_SPEC.md`.
 */

// Main entry point
export { PocketPrinter, type PrinterInfo, type PrinterEvents } from './printer.js';

// Documents
export { PrintDocument, PaperMode, type PrintElement } from './protocol/document.js';
export {
  buildJob,
  buildSegments,
  defaultOptions,
  type PrintOptions,
  type PrintSegment,
} from './protocol/job.js';

// Protocol
export * as commands from './protocol/commands.js';
export { Density, PrinterStatus } from './protocol/commands.js';
export * as escpos from './protocol/escpos.js';
export { Alignment, transliterate } from './protocol/escpos.js';
export { CreditFlowController } from './protocol/flow-control.js';
export { decode, toHex, type DecodedResponse } from './protocol/responses.js';
export {
  MonochromeBitmap,
  PrinterWidth,
  encodeBlackPixels,
  rasterCommand,
  bandedRasterCommands,
  threshold,
  orderedDither,
  floydSteinberg,
} from './protocol/raster.js';
export { columnsFor, wrap, columns } from './protocol/text-layout.js';

// Rendering
export {
  renderQR,
  renderBarcode,
  Symbology,
  type QRMatrix,
  type CodeOptions,
} from './render/codes.js';
export { barcodePattern, eanCheckDigit } from './render/barcode.js';
export {
  bitmapFromCanvas,
  bitmapFromImage,
  bitmapToCanvas,
  DitherMode,
  type RenderOptions,
} from './render/canvas.js';

// Transports
export type { Transport, PrinterDevice, NotificationHandler } from './transport/types.js';
export { WebBluetoothTransport } from './transport/web-bluetooth.js';
export { CapacitorTransport, type BleClientLike } from './transport/capacitor.js';
