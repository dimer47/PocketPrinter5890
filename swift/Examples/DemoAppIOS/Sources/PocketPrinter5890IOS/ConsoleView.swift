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
        Group {
            if setup.brand == .brother {
                brotherLog
            } else {
                hexLog
            }
        }
    }

    private var brotherLog: some View {
        List(brother.events.reversed()) { event in
            VStack(alignment: .leading, spacing: 2) {
                Text(event.date, style: .time)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                Text(event.text)
                    .font(.caption)
                    .foregroundColor(event.isError ? .red : .primary)
            }
        }
        .overlay {
            if brother.events.isEmpty {
                Text("brother.log.empty").foregroundColor(.secondary)
            }
        }
    }

    private var hexLog: some View {
        List(transport.log.suffix(300).reversed()) { entry in
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
        .navigationTitle("tab.console")
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
