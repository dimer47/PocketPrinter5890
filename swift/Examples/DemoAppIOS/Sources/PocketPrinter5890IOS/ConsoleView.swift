import PocketPrinter5890BLE
import SwiftUI

/// Console hexadecimale: indispensable pour verifier ce qui part et ce qui
/// revient, notamment les trames de credit.
///
/// Avec une Brother, le SDK parle seul a l'imprimante: la console montre
/// alors le journal Brother a la place des trames.
struct ConsoleView: View {
    @ObservedObject var transport: PocketPrinter5890BLE
    @ObservedObject var setup: PrinterSetup
    @ObservedObject var brother: BrotherPrinterService

    var body: some View {
        List {
            if setup.brand == .brother {
                brotherRows
            } else {
                hexRows
            }
        }
        .overlay {
            if setup.brand == .brother && brother.events.isEmpty {
                Text("brother.log.empty")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .navigationTitle("tab.console")
    }

    /// Meme gabarit que les trames: etiquette coloree, heure, message.
    /// Les infos de l'imprimante s'affichent en plus sous forme de tableau.
    private var brotherRows: some View {
        ForEach(brother.events.reversed()) { event in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tag(for: event))
                        .font(.caption2.weight(.bold))
                        .foregroundColor(tint(for: event))
                        .frame(width: 34, alignment: .leading)
                    Text(event.date, style: .time)
                        .font(.caption)
                        .lineLimit(1)
                }
                if event.fields.isEmpty && event.battery == nil {
                    Text(event.text)
                        .font(.caption2)
                        .foregroundColor(event.isError ? .red : .secondary)
                } else {
                    InfoCard(title: event.text, fields: event.fields, battery: event.battery)
                }
            }
        }
    }

    private func tag(for event: BrotherPrinterService.Event) -> String {
        if event.isError { return "ERR" }
        switch event.kind {
        case .search: return "SCAN"
        case .connection: return "LINK"
        case .print: return "PRT"
        case .info: return "INFO"
        case .general: return "SDK"
        }
    }

    private func tint(for event: BrotherPrinterService.Event) -> Color {
        if event.isError { return .red }
        switch event.kind {
        case .search: return .purple
        case .connection: return .orange
        case .print: return .blue
        case .info: return .teal
        case .general: return .secondary
        }
    }

    private var hexRows: some View {
        ForEach(transport.log.suffix(300).reversed()) { entry in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.direction.rawValue)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(color(for: entry.direction))
                        .frame(width: 34, alignment: .leading)
                    Text(entry.label)
                        .font(.caption)
                        .lineLimit(1)
                }
                Text(entry.hex)
                    .font(.caption2.monospaced())
                    .lineLimit(3)
                if !entry.decoded.isEmpty {
                    Text(entry.decoded)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func color(for direction: HexLogEntry.Direction) -> Color {
        switch direction {
        case .tx: return .blue
        case .rx: return .green
        case .error: return .red
        case .info: return .secondary
        }
    }
}

/// Infos de l'imprimante: une ligne par valeur, jauge pour la batterie.
private struct InfoCard: View {
    let title: String
    let fields: [BrotherField]
    let battery: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            if let battery {
                HStack(spacing: 8) {
                    Image(systemName: batteryIcon(battery))
                        .foregroundColor(batteryColor(battery))
                        .frame(width: 18)
                    Text("brother.info.batteryCharge")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView(value: Double(min(100, max(0, battery))), total: 100)
                        .tint(batteryColor(battery))
                    Text("\(battery) %")
                        .font(.caption.monospacedDigit())
                }
            }
            ForEach(fields, id: \.self) { field in
                HStack(spacing: 8) {
                    Image(systemName: field.icon)
                        .foregroundColor(.teal)
                        .frame(width: 18)
                    Text(field.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 8)
                    Text(field.value)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(10)
        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private func batteryColor(_ level: Int) -> Color {
        level < 20 ? .red : (level < 40 ? .orange : .green)
    }
}
