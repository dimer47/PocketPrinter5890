/**
 * Decoding of printer notifications.
 *
 * Frames arrive on two characteristics with different meanings, and telling
 * them apart matters: see `docs/PROTOCOL_SPEC.md` section 2.
 */

import { PrinterStatus } from './commands.js';

export interface DecodedResponse {
  kind: 'credit' | 'battery' | 'status' | 'text' | 'ack' | 'unknown';
  text: string;
  /** Battery percentage, when `kind` is 'battery'. */
  battery?: number;
  /** Parsed status, when `kind` is 'status'. */
  status?: PrinterStatus;
}

/**
 * Decodes a notification frame.
 *
 * Order matters: a `01 nn` credit frame must be recognised before anything
 * else, otherwise it gets mistaken for a command reply.
 */
export function decode(bytes: Uint8Array): DecodedResponse {
  // Credit frame — never a reply.
  if (bytes.length === 2 && bytes[0] === 0x01) {
    return { kind: 'credit', text: `Flow credit: +${bytes[1]} packet(s)` };
  }

  // "OK" acknowledgement.
  if (bytes.length === 2 && bytes[0] === 0x4f && bytes[1] === 0x4b) {
    return { kind: 'ack', text: 'OK' };
  }

  // Battery, in both observed shapes. The percentage is the second byte.
  const isBattery =
    (bytes.length === 3 && bytes[0] === 0x02) ||
    (bytes.length === 2 && bytes[0] === 0x00);
  if (isBattery) {
    const percent = bytes[1]!;
    if (percent > 0 && percent <= 100) {
      return { kind: 'battery', text: `Battery: ${percent}%`, battery: percent };
    }
  }

  // Single status byte.
  if (bytes.length === 1) {
    const status = new PrinterStatus(bytes[0]!);
    return { kind: 'status', text: `Status: ${status}`, status };
  }

  // Printable ASCII: model, firmware, serial number.
  const printable = Array.from(bytes).filter((b) => b >= 0x20 && b <= 0x7e);
  if (printable.length > 0) {
    const text = String.fromCharCode(...printable);
    return { kind: 'text', text };
  }

  return { kind: 'unknown', text: '' };
}

/** Formats bytes as uppercase hex, for logging. */
export function toHex(bytes: Uint8Array | number[]): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0').toUpperCase())
    .join(' ');
}
