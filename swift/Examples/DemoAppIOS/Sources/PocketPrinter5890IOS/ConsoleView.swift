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

    /// Meme gabarit que les trames: etiquette coloree, titre, detail.
    private var brotherRows: some View {
        ForEach(brother.events.reversed()) { event in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.isError ? "ERR" : "SDK")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(event.isError ? .red : .secondary)
                        .frame(width: 34, alignment: .leading)
                    Text(event.date, style: .time)
                        .font(.caption)
                        .lineLimit(1)
                }
                Text(event.text)
                    .font(.caption2)
                    .foregroundColor(event.isError ? .red : .secondary)
            }
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
