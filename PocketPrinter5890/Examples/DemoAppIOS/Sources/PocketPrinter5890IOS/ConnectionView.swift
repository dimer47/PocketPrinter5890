import PocketPrinter5890BLE
import PocketPrinter5890Kit
import SwiftUI

struct ConnectionView: View {
    @ObservedObject var transport: PocketPrinter5890BLE

    var body: some View {
        List {
            Section {
                if transport.isConnected {
                    DeviceStatusRow(
                        battery: transport.batteryPercent,
                        model: transport.deviceModel,
                        firmware: transport.deviceFirmware
                    )
                }
                Text(transport.stateText)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Section {
                Button(transport.isScanning ? "scan.stop" : "scan.start") {
                    transport.isScanning ? transport.stopScan() : transport.startScan()
                }
                if transport.isConnected {
                    Button("device.disconnect", role: .destructive) {
                        transport.disconnect()
                    }
                }
                Toggle("device.filter", isOn: $transport.showOnlyLikelyPrinters)
            }

            Section("devices.found") {
                if transport.devices.isEmpty {
                    Text("devices.none")
                        .foregroundColor(.secondary)
                }
                ForEach(transport.devices) { device in
                    Button {
                        transport.connect(to: device)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.body.weight(.medium))
                            if device.isLikelyL13 {
                                Text("device.candidate")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            Text("\(device.id.uuidString)  \(device.rssi) dBm")
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if transport.isConnected {
                Section("gatt.title") {
                    LabeledRow("Service", transport.selectedService)
                    LabeledRow("RX", transport.selectedRX)
                    LabeledRow("TX", transport.selectedTX)
                    LabeledRow("Notify", transport.selectedNotify)
                }

                Section {
                    Button("info.read") {
                        transport.readDeviceInformation()
                    }
                }
            }
        }
        .navigationTitle("app.title")
    }
}

struct LabeledRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
        }
    }
}

struct DeviceStatusRow: View {
    let battery: Int?
    let model: String?
    let firmware: String?

    var body: some View {
        HStack(spacing: 10) {
            if let battery {
                Image(systemName: symbol(for: battery))
                    .foregroundColor(color(for: battery))
                Text("\(battery) %")
                    .font(.callout.weight(.medium))
            } else {
                ProgressView()
                Text("battery.loading")
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let model {
                Text(model).font(.caption.weight(.medium))
            }
            if let firmware {
                Text(firmware).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func symbol(for level: Int) -> String {
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private func color(for level: Int) -> Color {
        switch level {
        case ..<15: return .red
        case ..<30: return .orange
        default: return .green
        }
    }
}
