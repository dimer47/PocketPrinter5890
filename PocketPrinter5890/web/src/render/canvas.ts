/**
 * Canvas rendering: turns anything drawable into a printable bitmap.
 *
 * This is the web counterpart of the CoreGraphics renderer in the Swift
 * library. Only the raster encoding is shared between the two; the drawing
 * itself is necessarily platform-specific.
 *
 * Requires a DOM. In Capacitor this works as-is since the web layer runs in a
 * WebView.
 */

import {
  MonochromeBitmap,
  PrinterWidth,
  threshold,
  orderedDither,
  floydSteinberg,
} from '../protocol/raster.js';

export enum DitherMode {
  /** Hard threshold. Use for text, barcodes and QR codes. */
  Threshold = 'threshold',
  /** Ordered 4x4. */
  Ordered = 'ordered',
  /** Error diffusion. Best for photographs. */
  FloydSteinberg = 'floyd-steinberg',
}

export interface RenderOptions {
  printWidth?: number;
  dither?: DitherMode;
  /** Threshold level, only used with `DitherMode.Threshold`. */
  level?: number;
}

/** Extracts grayscale pixels from a canvas. */
function toGrayscale(canvas: HTMLCanvasElement | OffscreenCanvas): {
  gray: Uint8Array;
  width: number;
  height: number;
} {
  const context = canvas.getContext('2d') as
    | CanvasRenderingContext2D
    | OffscreenCanvasRenderingContext2D
    | null;
  if (!context) throw new Error('Could not obtain a 2D context');

  const { width, height } = canvas;
  const data = context.getImageData(0, 0, width, height).data;
  const gray = new Uint8Array(width * height);

  for (let i = 0; i < width * height; i += 1) {
    const offset = i * 4;
    const alpha = data[offset + 3]! / 255;
    // Composite over white: a transparent pixel must not print black.
    const red = data[offset]! * alpha + 255 * (1 - alpha);
    const green = data[offset + 1]! * alpha + 255 * (1 - alpha);
    const blue = data[offset + 2]! * alpha + 255 * (1 - alpha);
    gray[i] = Math.round((red * 299 + green * 587 + blue * 114) / 1000);
  }
  return { gray, width, height };
}

/** Converts a canvas to a printable bitmap, scaling to the print width. */
export function bitmapFromCanvas(
  canvas: HTMLCanvasElement | OffscreenCanvas,
  options: RenderOptions = {},
): MonochromeBitmap {
  const printWidth = options.printWidth ?? PrinterWidth.MM58;
  const mode = options.dither ?? DitherMode.FloydSteinberg;

  let source = canvas;
  if (canvas.width !== printWidth) {
    const scale = printWidth / canvas.width;
    const height = Math.max(1, Math.round(canvas.height * scale));
    const scaled = createCanvas(printWidth, height);
    const context = scaled.getContext('2d') as CanvasRenderingContext2D;
    context.fillStyle = 'white';
    context.fillRect(0, 0, printWidth, height);
    context.drawImage(canvas as CanvasImageSource, 0, 0, printWidth, height);
    source = scaled;
  }

  const { gray, width, height } = toGrayscale(source);
  switch (mode) {
    case DitherMode.Threshold:
      return threshold(gray, width, height, options.level ?? 128);
    case DitherMode.Ordered:
      return orderedDither(gray, width, height);
    case DitherMode.FloydSteinberg:
      return floydSteinberg(gray, width, height);
  }
}

/** Converts an image element or bitmap to a printable bitmap. */
export function bitmapFromImage(
  image: CanvasImageSource & { width: number; height: number },
  options: RenderOptions = {},
): MonochromeBitmap {
  const printWidth = options.printWidth ?? PrinterWidth.MM58;
  const scale = printWidth / image.width;
  const height = Math.max(1, Math.round(image.height * scale));

  const canvas = createCanvas(printWidth, height);
  const context = canvas.getContext('2d') as CanvasRenderingContext2D;
  context.fillStyle = 'white';
  context.fillRect(0, 0, printWidth, height);
  context.drawImage(image, 0, 0, printWidth, height);

  return bitmapFromCanvas(canvas, options);
}

/** Renders a bitmap back into a canvas, for on-screen preview. */
export function bitmapToCanvas(bitmap: MonochromeBitmap): HTMLCanvasElement {
  const canvas = createCanvas(bitmap.width, bitmap.height) as HTMLCanvasElement;
  const context = canvas.getContext('2d') as CanvasRenderingContext2D;
  const image = context.createImageData(bitmap.width, bitmap.height);

  for (let y = 0; y < bitmap.height; y += 1) {
    for (let x = 0; x < bitmap.width; x += 1) {
      const bit = (bitmap.bytes[y * bitmap.widthBytes + (x >> 3)]! >> (7 - (x % 8))) & 1;
      const value = bit === 1 ? 0 : 255;
      const offset = (y * bitmap.width + x) * 4;
      image.data[offset] = value;
      image.data[offset + 1] = value;
      image.data[offset + 2] = value;
      image.data[offset + 3] = 255;
    }
  }
  context.putImageData(image, 0, 0);
  return canvas;
}

function createCanvas(width: number, height: number): HTMLCanvasElement | OffscreenCanvas {
  if (typeof document !== 'undefined') {
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    return canvas;
  }
  return new OffscreenCanvas(width, height);
}
