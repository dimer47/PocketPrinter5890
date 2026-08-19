/**
 * Transport abstraction.
 *
 * The protocol is identical everywhere; only the way a byte channel is
 * obtained differs. Implement this interface to support a new platform.
 *
 * Note that flow control is **not** the transport's responsibility: it lives
 * in the protocol layer, so it is written once rather than per adapter.
 */

/** Service and characteristic UUIDs. Only FF00 responds on this hardware. */
export const SERVICE_UUID = 0xff00;
export const WRITE_UUID = 0xff02;
export const NOTIFY_TX_UUID = 0xff01;
export const NOTIFY_STATUS_UUID = 0xff03;

/** Full-form UUIDs, required by some APIs. */
export const SERVICE_UUID_FULL = '0000ff00-0000-1000-8000-00805f9b34fb';
export const WRITE_UUID_FULL = '0000ff02-0000-1000-8000-00805f9b34fb';
export const NOTIFY_TX_UUID_FULL = '0000ff01-0000-1000-8000-00805f9b34fb';
export const NOTIFY_STATUS_UUID_FULL = '0000ff03-0000-1000-8000-00805f9b34fb';

/** A discovered device. */
export interface PrinterDevice {
  id: string;
  name: string;
  rssi?: number;
}

export type NotificationHandler = (bytes: Uint8Array) => void;
export type DisconnectHandler = () => void;

/** Byte channel to the printer. */
export interface Transport {
  readonly isConnected: boolean;

  /** Maximum bytes per write. 180 is reliable; the vendor app negotiates up to 512. */
  maxChunkSize: number;

  connect(): Promise<PrinterDevice>;
  disconnect(): Promise<void>;

  /** Writes a single chunk. Must not exceed `maxChunkSize`. */
  write(bytes: Uint8Array): Promise<void>;

  /** Registers a handler for incoming notifications. */
  onNotification(handler: NotificationHandler): void;

  /**
   * Registers a handler for unexpected disconnection.
   *
   * The printer going out of range or being switched off does not surface as
   * an error on the write path: without this the caller keeps believing it is
   * connected and queues bytes into the void.
   */
  onDisconnect(handler: DisconnectHandler): void;
}
