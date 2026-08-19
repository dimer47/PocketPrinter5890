/**
 * Text layout helpers.
 *
 * The firmware cuts overlong lines mid-character: "l'apres-midi." becomes
 * "l'apres-m" then "idi.". Wrap before sending.
 */

/** Columns available for a given width and size multiplier. */
export function columnsFor(printWidth: number, size = 1): number {
  return Math.max(1, Math.floor(printWidth / (12 * Math.max(1, size))));
}

/** Wraps text on spaces so no line exceeds `columns`. */
export function wrap(text: string, columns: number): string[] {
  if (columns <= 0) return [text];
  const lines: string[] = [];

  for (const paragraph of text.split('\n')) {
    let current = '';
    for (const word of paragraph.split(' ')) {
      const candidate = current === '' ? word : `${current} ${word}`;
      if (candidate.length <= columns) {
        current = candidate;
        continue;
      }
      if (current !== '') {
        lines.push(current);
        current = '';
      }
      // A word longer than a line has to be cut.
      let remainder = word;
      while (remainder.length > columns) {
        lines.push(remainder.slice(0, columns));
        remainder = remainder.slice(columns);
      }
      current = remainder;
    }
    lines.push(current);
  }
  return lines;
}

/**
 * Lays out a label on the left and a value on the right.
 *
 * The printer applies one alignment per line, so columns have to be built
 * with spacing. The label is truncated if both do not fit: the value is
 * usually the useful part.
 */
export function columns(left: string, right: string, width: number): string {
  const available = width - right.length - 1;
  if (available <= 0) return right.slice(-width);
  const label = left.length > available ? left.slice(0, available) : left;
  const padding = Math.max(1, width - label.length - right.length);
  return label + ' '.repeat(padding) + right;
}
