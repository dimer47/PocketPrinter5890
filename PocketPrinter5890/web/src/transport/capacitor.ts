/**
 * Capacitor transport, for iOS and Android from web code.
 *
 * Depends on `@capacitor-community/bluetooth-le`, which is **not** a
 * dependency of this package: the plugin is injected so the library stays
 * usable in a plain browser without pulling Capacitor in.
 *
 * ```ts
 * import { BleClient } from '@capacitor-community/bluetooth-le';
 * const transport = new CapacitorTransport(BleClient);
 * ```
 *
 * Untested: this adapter is written against the plugin's documented API but
 * has not been run on a device.
 */

import {
  type NotificationHandler,
  type PrinterDevice,
  type Transport,
  SERVICE_UUID_FULL,
  WRITE_UUID_FULL,
  NOTIFY_TX_UUID_FULL,
  NOTIFY_STATUS_UUID_FULL,
} from './types.js';

/** Subset of `BleClient` this transport needs. */
export interface BleClientLike {
  initialize(options?: unknown): Promise<void>;
  requestDevice(options?: unknown): Promise<{ deviceId: string; name?: string }>;
  connect(deviceId: string, onDisconnect?: (deviceId: string) => void): Promise<void>;
  disconnect(deviceId: string): Promise<void>;
  writeWithoutResponse(
    deviceId: string,
    service: string,
    characteristic: string,
    value: DataView,
  ): Promise<void>;
  startNotifications(
    deviceId: string,
    service: string,
    characteristic: string,
    callback: (value: DataView) => void,
  ): Promise<void>;
}

export class CapacitorTransport implements Transport {
  private deviceId?: string;
  private handlers: NotificationHandler[] = [];

  maxChunkSize = 180;

  constructor(private readonly ble: BleClientLike) {}

  get isConnected(): boolean {
    return this.deviceId !== undefined;
  }

  async connect(): Promise<PrinterDevice> {
    await this.ble.initialize();

    const device = await this.ble.requestDevice({
      namePrefix: 'Mini Pocket Printer',
      optionalServices: [SERVICE_UUID_FULL],
    });

    await this.ble.connect(device.deviceId, () => {
      this.deviceId = undefined;
    });
    this.deviceId = device.deviceId;

    for (const uuid of [NOTIFY_TX_UUID_FULL, NOTIFY_STATUS_UUID_FULL]) {
      try {
        await this.ble.startNotifications(device.deviceId, SERVICE_UUID_FULL, uuid, (value) => {
          const bytes = new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
          this.handlers.forEach((handler) => handler(bytes));
        });
      } catch {
        // A missing characteristic is not fatal.
      }
    }

    return { id: device.deviceId, name: device.name ?? 'Unknown' };
  }

  async disconnect(): Promise<void> {
    if (this.deviceId) await this.ble.disconnect(this.deviceId);
    this.deviceId = undefined;
  }

  async write(bytes: Uint8Array): Promise<void> {
    if (!this.deviceId) throw new Error('Not connected');
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    await this.ble.writeWithoutResponse(this.deviceId, SERVICE_UUID_FULL, WRITE_UUID_FULL, view);
  }

  onNotification(handler: NotificationHandler): void {
    this.handlers.push(handler);
  }
}
