/**
 * Standard ESC/POS command set.
 *
 * Beware: the printer implements only part of this standard. Commands the
 * firmware ignores are marked NOT SUPPORTED and print as literal text —
 * see `docs/PROTOCOL_SPEC.md` section 8.
 */

export enum Alignment {
  Left = 0,
  Center = 1,
  Right = 2,
}

/** `ESC @` — resets the printer and clears formatting. */
export const INIT: number[] = [0x1b, 0x40];

/** `LF` */
export const LINE_FEED: number[] = [0x0a];

/** `ESC a n` */
export const align = (alignment: Alignment): number[] => [0x1b, 0x61, alignment];

/** `ESC E n` */
export const bold = (on: boolean): number[] => [0x1b, 0x45, on ? 1 : 0];

/** `ESC - n` — 0 none, 1 thin, 2 thick. */
export const underline = (thickness: number): number[] => [0x1b, 0x2d, Math.min(thickness, 2)];

/**
 * `GS B n` — reverse video.
 *
 * NOT SUPPORTED by this firmware: no visible effect.
 */
export const inverted = (on: boolean): number[] => [0x1d, 0x42, on ? 1 : 0];

/** `GS ! n` — size multiplier, 1 to 8 on each axis. */
export function textSize(width: number, height: number): number[] {
  const w = Math.max(1, Math.min(8, width)) - 1;
  const h = Math.max(1, Math.min(8, height)) - 1;
  return [0x1d, 0x21, (w << 4) | h];
}

/** `ESC d n` — feed n lines. */
export const feedLines = (lines: number): number[] => [0x1b, 0x64, lines];

/** `ESC J n` — feed n dots, max 255. */
export const feedDots = (dots: number): number[] => [0x1b, 0x4a, Math.min(dots, 255)];

/**
 * Feeds an arbitrary number of dots.
 *
 * `ESC J` takes a single byte, so beyond 255 dots (~32 mm) the command is
 * repeated as many times as needed.
 */
export function feed(dots: number): number[] {
  const output: number[] = [];
  let remaining = dots;
  while (remaining > 0) {
    const step = Math.min(remaining, 255);
    output.push(...feedDots(step));
    remaining -= step;
  }
  return output;
}

/** `ESC 3 n` — line spacing in dots. */
export const lineSpacing = (dots: number): number[] => [0x1b, 0x33, dots];

/**
 * `ESC t n` — code page.
 *
 * NOT SUPPORTED by this firmware: it is ignored, and leaks a stray byte into
 * the output. Do not send it. Use {@link transliterate} instead.
 */
export const codePage = (page: number): number[] => [0x1b, 0x74, page];

/** Symbol replacements applied before falling back to diacritic stripping. */
const REPLACEMENTS: Record<string, string> = {
  '°': 'deg', '€': 'EUR', '£': 'GBP', '¥': 'JPY',
  '«': '"', '»': '"', '‘': "'", '’': "'",
  '“': '"', '”': '"', '–': '-', '—': '-',
  '…': '...', '×': 'x', '÷': '/', '±': '+/-',
  '¼': '1/4', '½': '1/2', '¾': '3/4', '²': '2', '³': '3',
  'œ': 'oe', 'Œ': 'OE', 'æ': 'ae', 'Æ': 'AE', 'ß': 'ss',
};

/**
 * Converts text to plain ASCII.
 *
 * The firmware renders anything outside ASCII 0x20–0x7E as a solid block,
 * whatever code page is declared. `18°C` becomes `18degC`, `café` becomes
 * `cafe`. A slightly approximate line beats an unreadable one.
 */
export function transliterate(text: string): string {
  let result = '';
  for (const character of text) {
    if (character.charCodeAt(0) < 128) {
      result += character;
      continue;
    }
    const replacement = REPLACEMENTS[character];
    if (replacement !== undefined) {
      result += replacement;
      continue;
    }
    // Strip diacritics: "é" -> "e", "ç" -> "c".
    const folded = character.normalize('NFD').replace(/[̀-ͯ]/g, '');
    result += /^[\x20-\x7e]*$/.test(folded) && folded.length > 0 ? folded : '?';
  }
  return result;
}

/** Encodes text as ASCII bytes. Call {@link transliterate} first. */
export function encode(text: string): number[] {
  const bytes: number[] = [];
  for (const character of text) {
    const code = character.charCodeAt(0);
    bytes.push(code < 128 ? code : 0x3f);
  }
  return bytes;
}

/** Text followed by a line feed. */
export const line = (text: string): number[] => [...encode(text), ...LINE_FEED];
