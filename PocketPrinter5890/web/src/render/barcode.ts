/**
 * Linear barcode generation, in pure TypeScript.
 *
 * The firmware does not implement `GS k`: sending it prints the command as
 * literal text (`<I{BMETEO2026`). Barcodes must be rasterised instead — which
 * is also what the vendor app does.
 *
 * No external dependency, so this works identically in a browser, in
 * Capacitor and in Node.
 */

export enum Symbology {
  Code128 = 'code128',
  Code39 = 'code39',
  EAN13 = 'ean13',
  EAN8 = 'ean8',
}

/** Code 128 patterns: 107 symbols, bar/space widths. */
const CODE128_WIDTHS: number[][] = [
  [2,1,2,2,2,2],[2,2,2,1,2,2],[2,2,2,2,2,1],[1,2,1,2,2,3],[1,2,1,3,2,2],
  [1,3,1,2,2,2],[1,2,2,2,1,3],[1,2,2,3,1,2],[1,3,2,2,1,2],[2,2,1,2,1,3],
  [2,2,1,3,1,2],[2,3,1,2,1,2],[1,1,2,2,3,2],[1,2,2,1,3,2],[1,2,2,2,3,1],
  [1,1,3,2,2,2],[1,2,3,1,2,2],[1,2,3,2,2,1],[2,2,3,2,1,1],[2,2,1,1,3,2],
  [2,2,1,2,3,1],[2,1,3,2,1,2],[2,2,3,1,1,2],[3,1,2,1,3,1],[3,1,1,2,2,2],
  [3,2,1,1,2,2],[3,2,1,2,2,1],[3,1,2,2,1,2],[3,2,2,1,1,2],[3,2,2,2,1,1],
  [2,1,2,1,2,3],[2,1,2,3,2,1],[2,3,2,1,2,1],[1,1,1,3,2,3],[1,3,1,1,2,3],
  [1,3,1,3,2,1],[1,1,2,3,1,3],[1,3,2,1,1,3],[1,3,2,3,1,1],[2,1,1,3,1,3],
  [2,3,1,1,1,3],[2,3,1,3,1,1],[1,1,2,1,3,3],[1,1,2,3,3,1],[1,3,2,1,3,1],
  [1,1,3,1,2,3],[1,1,3,3,2,1],[1,3,3,1,2,1],[3,1,3,1,2,1],[2,1,1,3,3,1],
  [2,3,1,1,3,1],[2,1,3,1,1,3],[2,1,3,3,1,1],[2,1,3,1,3,1],[3,1,1,1,2,3],
  [3,1,1,3,2,1],[3,3,1,1,2,1],[3,1,2,1,1,3],[3,1,2,3,1,1],[3,3,2,1,1,1],
  [3,1,4,1,1,1],[2,2,1,4,1,1],[4,3,1,1,1,1],[1,1,1,2,2,4],[1,1,1,4,2,2],
  [1,2,1,1,2,4],[1,2,1,4,2,1],[1,4,1,1,2,2],[1,4,1,2,2,1],[1,1,2,2,1,4],
  [1,1,2,4,1,2],[1,2,2,1,1,4],[1,2,2,4,1,1],[1,4,2,1,1,2],[1,4,2,2,1,1],
  [2,4,1,2,1,1],[2,2,1,1,1,4],[4,1,3,1,1,1],[2,4,1,1,1,2],[1,3,4,1,1,1],
  [1,1,1,2,4,2],[1,2,1,1,4,2],[1,2,1,2,4,1],[1,1,4,2,1,2],[1,2,4,1,1,2],
  [1,2,4,2,1,1],[4,1,1,2,1,2],[4,2,1,1,1,2],[4,2,1,2,1,1],[2,1,2,1,4,1],
  [2,1,4,1,2,1],[4,1,2,1,2,1],[1,1,1,1,4,3],[1,1,1,3,4,1],[1,3,1,1,4,1],
  [1,1,4,1,1,3],[1,1,4,3,1,1],[4,1,1,1,1,3],[4,1,1,3,1,1],[1,1,3,1,4,1],
  [1,1,4,1,3,1],[3,1,1,1,4,1],[4,1,1,1,3,1],[2,1,1,4,1,2],[2,1,1,2,1,4],
  [2,1,1,2,3,2],[2,3,3,1,1,1,2],
];

/** Code 39: nine elements per character, three of them wide. */
const CODE39_TABLE: Record<string, string> = {
  '0': '000110100', '1': '100100001', '2': '001100001', '3': '101100000',
  '4': '000110001', '5': '100110000', '6': '001110000', '7': '000100101',
  '8': '100100100', '9': '001100100', 'A': '100001001', 'B': '001001001',
  'C': '101001000', 'D': '000011001', 'E': '100011000', 'F': '001011000',
  'G': '000001101', 'H': '100001100', 'I': '001001100', 'J': '000011100',
  'K': '100000011', 'L': '001000011', 'M': '101000010', 'N': '000010011',
  'O': '100010010', 'P': '001010010', 'Q': '000000111', 'R': '100000110',
  'S': '001000110', 'T': '000010110', 'U': '110000001', 'V': '011000001',
  'W': '111000000', 'X': '010010001', 'Y': '110010000', 'Z': '011010000',
  '-': '010000101', '.': '110000100', ' ': '011000100', '$': '010101000',
  '/': '010100010', '+': '010001010', '%': '000101010', '*': '010010100',
};

const EAN_LEFT_ODD = [
  '0001101','0011001','0010011','0111101','0100011',
  '0110001','0101111','0111011','0110111','0001011',
];
const EAN_LEFT_EVEN = [
  '0100111','0110011','0011011','0100001','0011101',
  '0111001','0000101','0010001','0001001','0010111',
];
const EAN_RIGHT = [
  '1110010','1100110','1101100','1000010','1011100',
  '1001110','1010000','1000100','1001000','1110100',
];
/** Parity of the six left digits, selected by the first digit. */
const EAN_PARITY = [
  'OOOOOO','OOEOEE','OOEEOE','OOEEEO','OEOOEE',
  'OEEOOE','OEEEOO','OEOEOE','OEOEEO','OEEOEO',
];

/** EAN check digit, valid for both EAN-8 and EAN-13. */
export function eanCheckDigit(digits: number[]): number {
  let sum = 0;
  digits.forEach((digit, index) => {
    sum += digit * (index % 2 === 0 ? 1 : 3);
  });
  return (10 - (sum % 10)) % 10;
}

/** Bar pattern: true = black bar, false = space. One entry per module. */
export function barcodePattern(content: string, symbology: Symbology): boolean[] {
  if (content.length === 0) throw new Error('Empty barcode content');
  switch (symbology) {
    case Symbology.Code128: return code128Pattern(content);
    case Symbology.Code39: return code39Pattern(content);
    case Symbology.EAN13: return eanPattern(content, 13);
    case Symbology.EAN8: return eanPattern(content, 8);
  }
}

function code128Pattern(content: string): boolean[] {
  const values: number[] = [];
  for (const character of content) {
    const code = character.charCodeAt(0);
    if (code < 32 || code > 126) {
      throw new Error(`Character '${character}' is not supported by Code 128 (ASCII only)`);
    }
    values.push(code - 32);
  }

  const startB = 104;
  let checksum = startB;
  values.forEach((value, index) => {
    checksum += value * (index + 1);
  });
  checksum %= 103;

  const symbols = [startB, ...values, checksum, 106];
  const pattern: boolean[] = [];
  for (const symbol of symbols) {
    const widths = CODE128_WIDTHS[symbol]!;
    widths.forEach((width, index) => {
      for (let i = 0; i < width; i += 1) pattern.push(index % 2 === 0);
    });
  }
  return pattern;
}

function code39Pattern(content: string): boolean[] {
  const upper = content.toUpperCase();
  const encoded: string[] = [CODE39_TABLE['*']!];
  for (const character of upper) {
    const entry = CODE39_TABLE[character];
    if (entry === undefined || character === '*') {
      throw new Error(`Character '${character}' is not supported by Code 39`);
    }
    encoded.push(entry);
  }
  encoded.push(CODE39_TABLE['*']!);

  const pattern: boolean[] = [];
  encoded.forEach((entry, index) => {
    if (index > 0) pattern.push(false); // inter-character gap
    Array.from(entry).forEach((flag, position) => {
      const isBar = position % 2 === 0;
      const width = flag === '1' ? 3 : 1;
      for (let i = 0; i < width; i += 1) pattern.push(isBar);
    });
  });
  return pattern;
}

function eanPattern(content: string, length: number): boolean[] {
  const characters = Array.from(content);
  for (const character of characters) {
    if (!/[0-9]/.test(character)) {
      throw new Error(`Character '${character}' is not a digit`);
    }
  }

  // The check digit is computed when missing, verified when present.
  let digits = characters.map(Number);
  if (digits.length === length - 1) {
    digits = [...digits, eanCheckDigit(digits)];
  }
  if (digits.length !== length) {
    throw new Error(`Expected ${length - 1} or ${length} digits, got ${characters.length}`);
  }
  if (eanCheckDigit(digits.slice(0, -1)) !== digits[length - 1]) {
    throw new Error('Invalid check digit');
  }

  let bits = '101'; // start guard
  if (length === 13) {
    const parity = EAN_PARITY[digits[0]!]!;
    for (let index = 1; index <= 6; index += 1) {
      const table = parity[index - 1] === 'O' ? EAN_LEFT_ODD : EAN_LEFT_EVEN;
      bits += table[digits[index]!]!;
    }
    bits += '01010'; // centre guard
    for (let index = 7; index <= 12; index += 1) bits += EAN_RIGHT[digits[index]!]!;
  } else {
    for (let index = 0; index <= 3; index += 1) bits += EAN_LEFT_ODD[digits[index]!]!;
    bits += '01010';
    for (let index = 4; index <= 7; index += 1) bits += EAN_RIGHT[digits[index]!]!;
  }
  bits += '101'; // end guard

  return Array.from(bits).map((bit) => bit === '1');
}
