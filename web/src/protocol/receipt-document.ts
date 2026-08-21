/**
 * Receipt composition in native text.
 *
 * The counterpart of `renderReceipt`: same receipt, same layout, but composed
 * by the printer's internal font instead of being drawn and sent as pixels.
 *
 * Unlike the canvas renderer, this module has no DOM dependency: it works in
 * Node, in a worker, anywhere.
 */

import { PrintDocument } from './document.js';
import { Alignment, transliterate } from './escpos.js';
import { columnsFor, columns as alignColumns } from './text-layout.js';
import { PrinterWidth } from './raster.js';

import type { Receipt } from '../render/receipt.js';

/**
 * How a receipt is printed.
 *
 * Both paths exist because neither is better in every situation, and the
 * choice is visible on paper.
 */
export enum ReceiptPrintMode {
  /**
   * Native text: the printer composes with its internal font.
   *
   * Sharp and fast (a few dozen bytes per line), but limited to 32 columns,
   * no bold, no logo, and text must be transliterated to ASCII.
   */
  NativeText = 'nativeText',

  /**
   * Rasterised image: the receipt is drawn, then sent as pixels.
   *
   * Free layout, bold and accents available — this is what the vendor app
   * does. In exchange the result is softer and the job weighs thousands of
   * bytes.
   */
  RasterImage = 'rasterImage',
}

export const receiptPrintModeTitle = (mode: ReceiptPrintMode): string =>
  mode === ReceiptPrintMode.NativeText ? 'Native text' : 'Rasterised image';

export const receiptPrintModeDetail = (mode: ReceiptPrintMode): string =>
  mode === ReceiptPrintMode.NativeText
    ? 'Sharp and fast. 32 columns, no bold, no accents.'
    : 'Free layout, bold and accents. Softer, heavier.';

const money = (value: number): string =>
  value.toFixed(2).replace('.', ',');

const formatDate = (date: Date): string => {
  const pad = (value: number): string => String(value).padStart(2, '0');
  return (
    `${pad(date.getDate())}/${pad(date.getMonth() + 1)}/${date.getFullYear()} ` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}`
  );
};

const itemTotal = (item: Receipt['items'][number]): number =>
  item.unitPrice * item.quantity;

const receiptSum = (receipt: Receipt): number =>
  receipt.items.reduce((total, item) => total + itemTotal(item), 0);

/**
 * Builds the document from a receipt.
 *
 * @param columns text columns available; 32 at the native width.
 */
export function buildReceiptDocument(
  receipt: Receipt,
  columns: number = columnsFor(PrinterWidth.MM58),
): PrintDocument {
  const document = new PrintDocument();

  document.title(receipt.merchantName.toUpperCase());
  if (receipt.address) {
    document.add({
      type: 'text',
      value: receipt.address,
      alignment: Alignment.Center,
    });
  }
  document.add({
    type: 'text',
    value: formatDate(receipt.date),
    alignment: Alignment.Center,
  });
  document.add({ type: 'separator' });

  for (const item of receipt.items) {
    document.add({
      type: 'text',
      value: alignColumns(
        `${item.quantity}x ${item.name}`,
        money(itemTotal(item)),
        columns,
      ),
    });
  }

  document.add({ type: 'separator' });
  // Bold is requested but has no effect on this firmware: the line stays
  // readable through alignment, not weight.
  document.add({
    type: 'text',
    value: alignColumns('TOTAL', `${money(receiptSum(receipt))} EUR`, columns),
    bold: true,
  });

  if (receipt.footer) {
    document.add({ type: 'separator', character: '=' });
    document.add({
      type: 'text',
      value: receipt.footer,
      alignment: Alignment.Center,
    });
  }
  document.add({ type: 'feed', lines: 2 });
  return document;
}

/**
 * Text preview, character for character what will be printed.
 *
 * The preview and the print share one layout: what is shown is what comes out
 * of the paper.
 */
export function previewReceiptText(
  receipt: Receipt,
  columns: number = columnsFor(PrinterWidth.MM58),
  applyTransliteration = true,
): string {
  const lines: string[] = [];
  for (const element of buildReceiptDocument(receipt, columns).elements) {
    if (element.type === 'text') {
      lines.push(applyTransliteration ? transliterate(element.value) : element.value);
    } else if (element.type === 'separator') {
      lines.push((element.character ?? '-').repeat(columns));
    }
  }
  return lines.join('\n');
}
