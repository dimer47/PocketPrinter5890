/**
 * Rendering barcodes and QR codes into printable bitmaps.
 *
 * The firmware implements neither `GS k` nor `GS ( k`: both print as literal
 * text. Codes have to be rasterised, which is also what the vendor app does.
 */

import { MonochromeBitmap, PrinterWidth } from '../protocol/raster.js';
import { barcodePattern, Symbology } from './barcode.js';

/**
 * A square matrix of QR modules, true meaning a dark module.
 *
 * This library deliberately does **not** implement a QR encoder. Writing a
 * correct one (masking, penalty evaluation, format BCH) is error-prone, and a
 * wrong QR code looks perfectly fine to the eye while failing every scanner.
 * Use a proven library and pass its output here.
 *
 * Example with `qrcode-generator`:
 * ```ts
 * const qr = qrcode(0, 'M');
 * qr.addData(text);
 * qr.make();
 * const matrix = {
 *   size: qr.getModuleCount(),
 *   isDark: (x, y) => qr.isDark(y, x),
 * };
 * ```
 */
export interface QRMatrix {
  size: number;
  isDark(x: number, y: number): boolean;
}

export interface CodeOptions {
  /** Print width in dots. */
  printWidth?: number;
  /** Module size in pixels. Computed to fill about two thirds if omitted. */
  moduleSize?: number;
}

/**
 * Renders a QR matrix centred on the print width.
 *
 * @param quietZone Blank margin in modules. The standard requires 4; below
 *                  that many scanners fail.
 */
export function renderQR(
  matrix: QRMatrix,
  options: CodeOptions & { quietZone?: number } = {},
): MonochromeBitmap {
  const printWidth = options.printWidth ?? PrinterWidth.MM58;
  const quietZone = options.quietZone ?? 4;
  const totalModules = matrix.size + quietZone * 2;
  const scale = options.moduleSize ?? Math.max(1, Math.floor((printWidth * 2) / 3 / totalModules));
  const codeSize = Math.min(totalModules * scale, printWidth);

  const widthBytes = printWidth / 8;
  const bytes = new Uint8Array(widthBytes * codeSize);
  const originX = Math.floor((printWidth - codeSize) / 2);

  for (let y = 0; y < codeSize; y += 1) {
    const moduleY = Math.floor(y / scale) - quietZone;
    if (moduleY < 0 || moduleY >= matrix.size) continue;
    for (let x = 0; x < codeSize; x += 1) {
      const moduleX = Math.floor(x / scale) - quietZone;
      if (moduleX < 0 || moduleX >= matrix.size) continue;
      if (!matrix.isDark(moduleX, moduleY)) continue;
      const pixelX = originX + x;
      bytes[y * widthBytes + (pixelX >> 3)]! |= 0x80 >> (pixelX % 8);
    }
  }
  return new MonochromeBitmap(printWidth, codeSize, bytes);
}

/**
 * Renders a linear barcode centred on the print width.
 *
 * @param quietZone Blank side margin in pixels.
 */
export function renderBarcode(
  content: string,
  symbology: Symbology = Symbology.Code128,
  options: CodeOptions & { height?: number; quietZone?: number } = {},
): MonochromeBitmap {
  const printWidth = options.printWidth ?? PrinterWidth.MM58;
  const height = Math.max(8, options.height ?? 80);
  const quietZone = options.quietZone ?? 20;

  const pattern = barcodePattern(content, symbology);
  const available = Math.max(1, printWidth - quietZone * 2);
  const scale = options.moduleSize ?? Math.max(1, Math.floor(available / pattern.length));
  const codeWidth = Math.min(pattern.length * scale, printWidth);

  const widthBytes = printWidth / 8;
  const bytes = new Uint8Array(widthBytes * height);
  const originX = Math.floor((printWidth - codeWidth) / 2);

  for (let x = 0; x < codeWidth; x += 1) {
    const index = Math.floor(x / scale);
    if (index >= pattern.length || !pattern[index]) continue;
    const pixelX = originX + x;
    for (let y = 0; y < height; y += 1) {
      bytes[y * widthBytes + (pixelX >> 3)]! |= 0x80 >> (pixelX % 8);
    }
  }
  return new MonochromeBitmap(printWidth, height, bytes);
}

export { Symbology } from './barcode.js';
