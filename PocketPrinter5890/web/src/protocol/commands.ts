/**
 * Proprietary command set, ported from the LuckPrinter SDK found in the
 * official `com.printer.lidloffice` application.
 *
 * Byte sequences are documented in `docs/PROTOCOL_SPEC.md`. Commands marked
 * UNVERIFIED were transcribed from the SDK but never executed on hardware:
 * the SDK covers 150+ printer models and nothing guarantees this one
 * implements them.
 */

/** Print density. */
export enum Density {
  Light = 0,
  Medium = 1,
  Dark = 2,
}

/**
 * Enables the print motor.
 *
 * Without this the firmware acknowledges every command and executes nothing,
 * not even a paper feed.
 */
export const enablePrinter = (mode = 3): number[] => [0x10, 0xff, 0xf1, mode];

/**
 * Wake-up.
 *
 * This is a **separate write**, not padding appended to `enablePrinter`.
 * Several public write-ups get this wrong; sending them concatenated fails.
 */
export const WAKEUP: number[] = new Array(12).fill(0x00);

/** Ends a print job and triggers the actual printing. */
export const STOP_PRINT_JOB: number[] = [0x10, 0xff, 0xf1, 0x45];

/** Positions the next label. Label mode only — wastes paper on a roll. */
export const POSITION: number[] = [0x1d, 0x0c];

/**
 * Declares a fixed label length. Label mode only.
 *
 * Sending this on continuous paper makes the printer feed to the end of the
 * declared length.
 */
export const setPaperType = (type = 1, length = 32): number[] => [0x1f, 0x80, type, length];

/** Sets print density. */
export const setDensity = (density: Density): number[] => [0x10, 0xff, 0x10, 0x00, density];

// --- Read commands, replies arrive on FF01 ---

export const READ_MODEL: number[] = [0x10, 0xff, 0x20, 0xf0];
export const READ_FIRMWARE: number[] = [0x10, 0xff, 0x20, 0xf1];
export const READ_SERIAL: number[] = [0x10, 0xff, 0x20, 0xf2];
export const READ_BOOTLOADER: number[] = [0x10, 0xff, 0x20, 0xef];
export const READ_BATTERY: number[] = [0x10, 0xff, 0x50, 0xf1];
export const READ_STATUS: number[] = [0x10, 0xff, 0x40];
export const READ_DENSITY: number[] = [0x10, 0xff, 0x11];
export const READ_SPEED: number[] = [0x10, 0xff, 0x20, 0xa0];
export const READ_AUTO_SHUTDOWN: number[] = [0x10, 0xff, 0x13];
export const READ_TIME_FORMAT: number[] = [0x10, 0xff, 0xb0];
export const READ_SETTINGS: number[] = [0x10, 0xff, 0x70];

// --- Write commands. Everything below is UNVERIFIED on this firmware ---

/**
 * Auto power-off delay, in minutes.
 *
 * Two bytes, **big-endian**. Note that `setWidth` below uses the opposite
 * order: the SDK is not consistent about this.
 *
 * UNVERIFIED. Passing 0 to disable power-off is a common convention but has
 * not been confirmed; read back with `READ_AUTO_SHUTDOWN` to see what the
 * firmware actually stored.
 */
export const setAutoShutdown = (minutes: number): number[] => [
  0x10, 0xff, 0x12,
  Math.floor(minutes / 256) & 0xff,
  minutes % 256,
];

/** Print width in dots. Two bytes, **little-endian**. UNVERIFIED. */
export const setWidth = (dots: number): number[] => [
  0x10, 0xff, 0x15,
  dots % 256,
  Math.floor(dots / 256) & 0xff,
];

/** Print speed. UNVERIFIED. */
export const setSpeed = (level: number): number[] => [0x10, 0xff, 0xc0, level];

/** Print head heating level. UNVERIFIED. */
export const setHeatingLevel = (level: number): number[] => [0x1f, 0x70, 0x01, level];

/** Printer mode. UNVERIFIED. */
export const setPrinterMode = (mode: number): number[] => [0x10, 0xff, 0x30, 0x27, mode];

/** Factory reset. UNVERIFIED and **destructive** if supported. */
export const FACTORY_RESET: number[] = [0x10, 0xff, 0x04];

/** Client platform declaration. UNVERIFIED. */
export const SET_PLATFORM: number[] = [0xfc, 0xff, 0x00, 0x02, 0x45, 0x02, 0x00, 0x46];

/**
 * Sets the internal clock. UNVERIFIED.
 *
 * The `10 FF 53 4A <format>` header precedes the date; sending the seven
 * date bytes alone does nothing.
 */
export function setClock(date: Date, format = 0): number[] {
  const year = date.getFullYear();
  return [
    0x10, 0xff, 0x53, 0x4a, format,
    Math.floor(year / 256) & 0xff,
    year % 256,
    date.getMonth() + 1,
    date.getDate(),
    date.getHours(),
    date.getMinutes(),
    date.getSeconds(),
  ];
}

/** Cut marks. UNVERIFIED. */
export const MARK_FIRST: number[] = [0x1b, 0xbb, 0xcc];
export const MARK_LAST: number[] = [0x1b, 0xbb, 0xbb];
export const MARK_INTERMEDIATE: number[] = [0x1b, 0xbb, 0xaa];

/** Reverse feed, in dots. UNVERIFIED. */
export const reverseFeed = (dots: number): number[] => [0x1f, 0x11, 0x11, dots];

/** Automatic positioning. UNVERIFIED. */
export const autoPosition = (value: number): number[] => [0x1f, 0x11, value];

/**
 * Printer status bitfield, as returned by `READ_STATUS`.
 *
 * Not to be confused with `01 nn` flow-control credit frames, which are not
 * status at all.
 */
export class PrinterStatus {
  constructor(readonly raw: number) {}

  get isPrinting(): boolean { return (this.raw & 0x01) !== 0; }
  get isCoverOpen(): boolean { return (this.raw & 0x02) !== 0; }
  get isPaperEmpty(): boolean { return (this.raw & 0x04) !== 0; }
  get isBatteryLow(): boolean { return (this.raw & 0x08) !== 0; }
  get isCharging(): boolean { return (this.raw & 0x20) !== 0; }
  get isOverheating(): boolean { return (this.raw & 0x50) !== 0; }

  /** States that genuinely prevent printing. */
  get isBlocking(): boolean {
    return this.isCoverOpen || this.isPaperEmpty || this.isOverheating;
  }

  toString(): string {
    const parts: string[] = [];
    if (this.isPrinting) parts.push('printing');
    if (this.isCoverOpen) parts.push('cover open');
    if (this.isPaperEmpty) parts.push('no paper');
    if (this.isBatteryLow) parts.push('battery low');
    if (this.isCharging) parts.push('charging');
    if (this.isOverheating) parts.push('overheating');
    return parts.length ? parts.join(', ') : 'ready';
  }
}
