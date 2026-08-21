import PocketPrinter5890BLE
import PocketPrinter5890Kit
import SwiftUI

struct PrintToolsView: View {
    @ObservedObject var transport: PocketPrinter5890BLE
    @Binding var options: PrintOptions

    @State private var freeText = NSLocalizedString("text.sample", comment: "")
    @State private var textSize = 1
    @State private var textAlignment: ESCPOS.Alignment = .left
    @State private var codeContent = "https://exemple.fr"

    var body: some View {
        List {
            Section("text.native") {
                TextEditor(text: $freeText)
                    .frame(height: 90)
                    .font(.body.monospaced())
                Picker("settings.alignment", selection: $textAlignment) {
                    ForEach(ESCPOS.Alignment.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                Stepper(
                    String(format: NSLocalizedString("text.size", comment: ""), textSize),
                    value: $textSize, in: 1...4
                )
                // Pas d'interrupteur « gras »: le firmware A2Y accepte
                // `ESC E` sans l'appliquer, constate sur papier ici et sur
                // Android. Un reglage sans effet ferait croire a une panne.
                Text("text.boldUnsupported")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("print.text") {
                    printer().print(
                        text: freeText,
                        size: textSize,
                        alignment: textAlignment,
                        options: options
                    )
                }
                .disabled(!transport.isConnected || freeText.isEmpty)
            }

            Section("codes.section") {
                TextField("codes.content", text: $codeContent)
                Button("codes.qr") { printQR() }
                    .disabled(!transport.isConnected || codeContent.isEmpty)
                Button("codes.barcode") { printBarcode() }
                    .disabled(!transport.isConnected || codeContent.isEmpty)
            }

            Section("demos.section") {
                Button("demo.weather") {
                    printer().print(DemoDocuments.weatherAndHoroscope(), options: options)
                }
                Button("demo.typography") {
                    printer().print(DemoDocuments.typographySampler(), options: options)
                }
                Button("print.pattern") { printPattern() }
                Button("demo.codePages") {
                    printer().print(DemoDocuments.codePageProbe(), options: options)
                }
            }
            .disabled(!transport.isConnected)

            Section {
                Button("print.clearPaper") {
                    printer().print(PrintDocument(), options: options)
                }
                .disabled(!transport.isConnected)
            }
        }
        .navigationTitle("tab.tools")
    }

    private func printer() -> PocketPrinter {
        PocketPrinter(transport: transport, options: options)
    }

    private func printQR() {
        guard let element = try? PrintElement.qr(codeContent, printWidth: options.width.pixels) else {
            return
        }
        printer().print(PrintDocument(elements: [element]), options: options)
    }

    private func printBarcode() {
        // Code 128 accepte tout l'ASCII imprimable, contrairement aux
        // symbologies numeriques.
        guard let element = try? PrintElement.code(
            codeContent, symbology: .code128, printWidth: options.width.pixels
        ) else {
            transport.recordLocalError(NSLocalizedString("codes.invalid", comment: ""))
            return
        }
        printer().print(PrintDocument(elements: [element]), options: options)
    }

    private func printPattern() {
        do {
            let bitmap = try ReceiptRenderer(width: options.width.pixels).testPattern(height: 120)
            transport.send(PrintJobBuilder.segments(bitmap: bitmap, options: options))
        } catch {
            transport.recordLocalError(
                String(format: NSLocalizedString("error.pattern", comment: ""),
                       error.localizedDescription)
            )
        }
    }
}
