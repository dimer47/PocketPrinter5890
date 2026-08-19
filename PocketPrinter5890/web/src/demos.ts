/**
 * Demonstration documents.
 *
 * Ported from the Swift library so both implementations print the same
 * things, which makes them comparable on paper.
 */

import { PrintDocument } from './protocol/document.js';
import { Alignment } from './protocol/escpos.js';
import { columns } from './protocol/text-layout.js';
import {
  MonochromeBitmap,
  PrinterWidth,
  encodeBlackPixels,
} from './protocol/raster.js';

/**
 * Weather bulletin and horoscope, both fictional.
 *
 * A showcase: multiple sizes, bold, underline, alignments, separators and
 * aligned columns.
 */
export function weatherAndHoroscope(date = new Date()): PrintDocument {
  const document = new PrintDocument();

  document.text(' DAILY BULLETIN ', { bold: true, alignment: Alignment.Center });
  document.centered(date.toLocaleString());
  document.separator('=');

  // --- Weather
  document.text('WEATHER', { size: 2, bold: true });
  document.feed(1);
  document.text('Lille', { bold: true, underline: true });
  document.text('Hazy, brightening in the afternoon.');
  document.feed(1);

  document.text('18degC', { size: 3, bold: true, alignment: Alignment.Center });
  document.centered('feels like 16degC');
  document.feed(1);

  for (const [label, value] of [
    ['Min / Max', '12deg / 21deg'],
    ['Wind', '23 km/h SW'],
    ['Humidity', '68 %'],
    ['Rain', '20 %'],
    ['UV', '4 moderate'],
  ] as const) {
    document.text(columns(label, value, 32));
  }

  document.separator('-');

  // --- Horoscope
  document.text('HOROSCOPE', { size: 2, bold: true, alignment: Alignment.Right });
  document.feed(1);
  document.text('ARIES', { size: 2, bold: true, alignment: Alignment.Center });
  document.centered('21 March - 19 April');
  document.feed(1);

  document.text('A good day for technical projects. Your persistence pays off.');
  document.feed(1);

  for (const [label, value] of [
    ['Love', '***'],
    ['Work', '*****'],
    ['Health', '****'],
  ] as const) {
    document.text(columns(label, value, 32));
  }

  document.separator('=');
  return document;
}

/** One line per capability, to see exactly what the firmware honours. */
export function typographySampler(): PrintDocument {
  const document = new PrintDocument();

  document.text(' AVAILABLE STYLES ', { bold: true, alignment: Alignment.Center });
  document.separator('=');

  document.text('Normal text');
  document.text('Bold text', { bold: true });
  document.text('Underlined text', { underline: true });
  // Reverse video is not implemented by this firmware: expect no change.
  document.text('Reverse video (unsupported)', { inverted: true });
  document.separator('-');

  document.text('Left aligned');
  document.centered('Centred');
  document.text('Right aligned', { alignment: Alignment.Right });
  document.separator('-');

  // Beyond size 4 a line no longer fits across 384 dots.
  for (let size = 1; size <= 4; size += 1) {
    document.text(`Size ${size}`, { size });
  }
  document.separator('-');

  document.text('Digits: 0123456789');
  document.text('Symbols: !?@#%&*()[]{}/\\');
  // Transliteration turns these into ASCII before sending.
  document.text('Accents: éèàûç °C 12 €');

  return document;
}

/**
 * Code page probe.
 *
 * Prints the same accented bytes after each `ESC t` variant. On this
 * firmware all nine lines come out identical and unreadable, which is how
 * the limitation was established: the command is ignored.
 *
 * Kept as a diagnostic for other models, which may behave differently.
 */
export function codePageProbe(): PrintDocument {
  const document = new PrintDocument();

  document.text('CODE PAGE PROBE', { bold: true, alignment: Alignment.Center });
  document.separator('=');
  document.text('ASCII reference:');
  document.text('degre C, aout, ete');
  document.separator('-');

  const pages: Array<[number, string]> = [
    [0, 'PC437 (USA)'],
    [1, 'Katakana'],
    [2, 'PC850 (multilingual)'],
    [3, 'PC860 (Portuguese)'],
    [4, 'PC863 (Canadian)'],
    [5, 'PC865 (Nordic)'],
    [6, 'Western Europe'],
    [19, 'PC858 (euro)'],
    [16, 'WPC1252'],
  ];

  for (const [page, label] of pages) {
    document.raw([0x1b, 0x74, page]);
    // The label goes through untouched: transliteration would defeat the test.
    document.raw([...Array.from(`${page}: ${label}`).map((c) => c.charCodeAt(0)), 0x0a]);
    // `° é è à û ç` in their CP1252 values.
    document.raw([0xb0, 0x20, 0xe9, 0x20, 0xe8, 0x20, 0xe0, 0x20, 0xfb, 0x20, 0xe7, 0x0a]);
  }

  document.separator('=');
  document.centered('A correct line names the right table');
  return document;
}

/**
 * Alignment pattern.
 *
 * The frame must span the full paper width; a wide blank margin on one side
 * means the configured width is wrong.
 */
export function testPattern(
  printWidth: number = PrinterWidth.MM58,
  height = 120,
): MonochromeBitmap {
  const pixels: boolean[] = new Array(printWidth * height).fill(false);
  const set = (x: number, y: number): void => {
    if (x >= 0 && x < printWidth && y >= 0 && y < height) {
      pixels[y * printWidth + x] = true;
    }
  };

  for (let x = 0; x < printWidth; x += 1) {
    set(x, 0);
    set(x, height - 1);
    // Ruler along the top, long marks every 64 dots.
    if (x % 8 === 0) for (let y = 0; y < (x % 64 === 0 ? 20 : 10); y += 1) set(x, y);
    // Solid bar: reveals a mis-set width.
    for (let y = height - 30; y < height - 18; y += 1) set(x, y);
  }
  for (let y = 0; y < height; y += 1) {
    set(0, y);
    set(printWidth - 1, y);
  }

  // Density checkerboard.
  for (let row = 0; row < 6; row += 1) {
    for (let column = 0; column < 12; column += 1) {
      if ((row + column) % 2 !== 0) continue;
      for (let y = 0; y < 6; y += 1) {
        for (let x = 0; x < 6; x += 1) {
          set(10 + column * 6 + x, 34 + row * 6 + y);
        }
      }
    }
  }

  return encodeBlackPixels(pixels, printWidth, height);
}
