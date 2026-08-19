/**
 * High-level print document.
 *
 * Describe what to print; `buildJob` turns it into printer bytes.
 */

import { Alignment } from './escpos.js';
import type { MonochromeBitmap } from './raster.js';

export type PrintElement =
  | {
      type: 'text';
      value: string;
      size?: number;
      bold?: boolean;
      underline?: boolean;
      inverted?: boolean;
      alignment?: Alignment;
    }
  | { type: 'image'; bitmap: MonochromeBitmap }
  | { type: 'separator'; character?: string }
  | { type: 'feed'; lines: number }
  | { type: 'raw'; bytes: number[] };

/** A document is just an ordered list of elements. */
export class PrintDocument {
  constructor(public elements: PrintElement[] = []) {}

  add(element: PrintElement): this {
    this.elements.push(element);
    return this;
  }

  /** Plain line of text. */
  text(value: string, options: Omit<Extract<PrintElement, { type: 'text' }>, 'type' | 'value'> = {}): this {
    return this.add({ type: 'text', value, ...options });
  }

  /** Large, bold, centred. */
  title(value: string): this {
    return this.add({ type: 'text', value, size: 2, bold: true, alignment: Alignment.Center });
  }

  centered(value: string): this {
    return this.add({ type: 'text', value, alignment: Alignment.Center });
  }

  separator(character = '-'): this {
    return this.add({ type: 'separator', character });
  }

  image(bitmap: MonochromeBitmap): this {
    return this.add({ type: 'image', bitmap });
  }

  feed(lines: number): this {
    return this.add({ type: 'feed', lines });
  }

  /** Escape hatch for a command the library does not cover. */
  raw(bytes: number[]): this {
    return this.add({ type: 'raw', bytes });
  }
}

/** Paper handling mode. */
export enum PaperMode {
  /** Receipt roll: stops at the end of the content. */
  Continuous = 'continuous',
  /** Fixed-length labels, with positioning between each. */
  Label = 'label',
}
