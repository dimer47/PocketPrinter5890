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
/**
 * `ESC E n` — gras.
 *
 * Attention: le firmware A2Y **accepte la commande sans l'appliquer**.
 * Constate sur papier depuis macOS/iOS et depuis Android. Pour du gras
 * reellement visible, rendre le texte en image et l'envoyer en raster, comme
 * le fait l'application officielle pour tout son texte.
 */
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

/**
 * Symbol replacements applied before falling back to diacritic stripping.
 *
 * Without an entry here, a non-ASCII character with no diacritic to strip
 * ends up as `?` on paper. Word processors produce plenty of these without
 * the user typing them: non-breaking spaces before colons in French,
 * typographic dashes, curly quotes.
 *
 * Written as escapes rather than literals: several of these characters are
 * indistinguishable from one another — or invisible — when read as source.
 */
const REPLACEMENTS: Record<string, string> = {
  // Currency and units
  '\u00B0': 'deg', '\u20AC': 'EUR', '\u00A3': 'GBP', '\u00A5': 'JPY',
  '\u00A2': 'c', '\u2116': 'No',

  // Quotes and apostrophes
  '\u00AB': '"', '\u00BB': '"', '\u2018': "'", '\u2019': "'",
  '\u201C': '"', '\u201D': '"', '\u201A': ',', '\u201E': '"',
  '\u2039': '<', '\u203A': '>',
  '\u2032': "'", '\u2033': '"',

  // Dashes: a wide family, and word processors readily swap an em dash in
  // for two hyphens.
  '\u2010': '-', '\u2011': '-', '\u2012': '-',
  '\u2013': '-', '\u2014': '-', '\u2015': '-',
  '\u2212': '-', '\u00AD': '',

  // Spaces: non-breaking and thin. Left alone, each one becomes a `?` in the
  // middle of a sentence — most visible in French, where a non-breaking
  // space precedes `:` and `»`.
  '\u00A0': ' ', '\u202F': ' ', '\u2009': ' ',
  '\u2007': ' ', '\u2008': ' ', '\u200A': ' ', '\u2002': ' ',
  '\u2003': ' ', '\u200B': '',

  // Punctuation and signs
  '\u2026': '...', '\u00D7': 'x', '\u00F7': '/', '\u00B1': '+/-',
  '\u2044': '/', '\u00A7': 'S', '\u00B6': 'P',
  '\u2020': '+', '\u2021': '++', '\u00B7': '-',
  '\u2022': '-', '\u00A9': '(c)', '\u00AE': '(R)',
  '\u2122': '(TM)', '\u00BF': '?', '\u00A1': '!',

  // Comparisons and arrows
  '\u2264': '<=', '\u2265': '>=', '\u2260': '!=',
  '\u2192': '->', '\u2190': '<-', '\u2194': '<->',
  '\u21D2': '=>', '\u221E': 'inf',

  // Solid symbols: with no ASCII equivalent, leave a visible mark rather
  // than a question mark.
  '\u2713': 'v', '\u2714': 'v', '\u2717': 'x', '\u2718': 'x',
  '\u25CF': '*', '\u25CB': 'o', '\u25A0': '#', '\u25A1': '#',
  '\u2605': '*', '\u2606': '*',

  // Fractions and superscripts
  '\u00BC': '1/4', '\u00BD': '1/2', '\u00BE': '3/4',
  '\u2153': '1/3', '\u2154': '2/3',
  '\u00B2': '2', '\u00B3': '3', '\u00B9': '1',

  // Ligatures
  '\u0153': 'oe', '\u0152': 'OE', '\u00E6': 'ae', '\u00C6': 'AE',
  '\u00DF': 'ss', '\u0133': 'ij', '\u0132': 'IJ',
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
