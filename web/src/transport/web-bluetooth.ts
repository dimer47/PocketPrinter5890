/**
 * Web Bluetooth transport, for Chrome, Edge and Opera.
 *
 * Not available in Firefox or Safari: both vendors declined to implement the
 * API. Use the Capacitor transport on those platforms.
 *
 * The browser requires a **user gesture** to open the device chooser, so
 * `connect()` must be called from a click handler. There is no silent
 * reconnection.
 */

import {
  type DisconnectHandler,
  type NotificationHandler,
  type PrinterDevice,
  type Transport,
  SERVICE_UUID,
  WRITE_UUID,
  NOTIFY_TX_UUID,
  NOTIFY_STATUS_UUID,
} from './types.js';

export class WebBluetoothTransport implements Transport {
  private device?: BluetoothDevice;
  private writeCharacteristic?: BluetoothRemoteGATTCharacteristic;
  private handlers: NotificationHandler[] = [];
  private disconnectHandlers: DisconnectHandler[] = [];

  maxChunkSize = 180;

  get isConnected(): boolean {
    return this.device?.gatt?.connected ?? false;
  }

  /** Whether the current browser supports Web Bluetooth at all. */
  static get isSupported(): boolean {
    return typeof navigator !== 'undefined' && 'bluetooth' in navigator;
  }

  async connect(): Promise<PrinterDevice> {
    if (!WebBluetoothTransport.isSupported) {
      throw new Error(
        'Web Bluetooth is unavailable. Chrome, Edge or Opera is required; ' +
        'Firefox and Safari do not implement it.',
      );
    }

    // The printer does not advertise its service UUIDs, so filtering by
    // service finds nothing: filter by name prefix and request the service
    // as optional.
    this.device = await navigator.bluetooth.requestDevice({
      filters: [
        { namePrefix: 'Mini Pocket Printer' },
        { namePrefix: 'MPT' },
        { namePrefix: 'PT-' },
      ],
      optionalServices: [SERVICE_UUID],
    });

    // Switching the printer off or walking out of range does not fail the
    // write path: without this event the caller never learns it is gone.
    this.device.addEventListener('gattserverdisconnected', () => {
      this.writeCharacteristic = undefined;
      this.disconnectHandlers.forEach((handler) => handler());
    });

    const server = await this.device.gatt?.connect();
    if (!server) throw new Error('GATT connection failed');

    const service = await server.getPrimaryService(SERVICE_UUID);
    this.writeCharacteristic = await service.getCharacteristic(WRITE_UUID);

    // Both notify characteristics carry different traffic: FF01 replies,
    // FF03 status and flow-control credits.
    for (const uuid of [NOTIFY_TX_UUID, NOTIFY_STATUS_UUID]) {
      try {
        const characteristic = await service.getCharacteristic(uuid);
        await characteristic.startNotifications();
        characteristic.addEventListener('characteristicvaluechanged', (event) => {
          const value = (event.target as BluetoothRemoteGATTCharacteristic).value;
          if (!value) return;
          const bytes = new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
          this.handlers.forEach((handler) => handler(bytes));
        });
      } catch {
        // A missing characteristic is not fatal: FF01 alone is enough to
        // receive replies.
      }
    }

    return {
      id: this.device.id,
      name: this.device.name ?? 'Unknown',
    };
  }

  async disconnect(): Promise<void> {
    this.device?.gatt?.disconnect();
    this.writeCharacteristic = undefined;
  }

  async write(bytes: Uint8Array): Promise<void> {
    if (!this.writeCharacteristic) throw new Error('Not connected');
    // Write without response: the printer paces us with credits instead.
    await this.writeCharacteristic.writeValueWithoutResponse(bytes as BufferSource);
  }

  onNotification(handler: NotificationHandler): void {
    this.handlers.push(handler);
  }

  onDisconnect(handler: DisconnectHandler): void {
    this.disconnectHandlers.push(handler);
  }
}
