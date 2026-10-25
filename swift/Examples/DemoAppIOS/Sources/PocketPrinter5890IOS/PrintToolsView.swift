import PocketPrinter5890BLE
import PocketPrinter5890Kit
import SwiftUI
import UniformTypeIdentifiers

struct PrintToolsView: View {
    @ObservedObject var transport: PocketPrinter5890BLE
    @ObservedObject var setup: PrinterSetup
    @ObservedObject var brother: BrotherPrinterService
    @Binding var options: PrintOptions

    @State private var freeText = NSLocalizedString("text.sample", comment: "")
    @State private var textSize = 1
    @State private var textAlignment: ESCPOS.Alignment = .left
    @State private var codeContent = "https://exemple.fr"
    @State private var pickingPDF = false

    var body: some View {
        List {
            if dispatcher.isBrother && brother.activity == .printing {
                Section {
                    Text(brother.status).font(.callout).foregroundColor(.secondary)
                    Button("brother.cancel", role: .destructive) { brother.cancelPrint() }
                }
            }

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
                if !dispatcher.isBrother {
                    Text("text.boldUnsupported")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("print.text") {
                    dispatcher.print(text: freeText, size: textSize, alignment: textAlignment)
                }
                .disabled(!dispatcher.isReady || freeText.isEmpty)
            }

            Section("codes.section") {
                TextField("codes.content", text: $codeContent)
                Button("codes.qr") { printQR() }
                    .disabled(!dispatcher.isReady || codeContent.isEmpty)
                Button("codes.barcode") { printBarcode() }
                    .disabled(!dispatcher.isReady || codeContent.isEmpty)
            }

            if dispatcher.isBrother {
                Section {
                    Button("pdf.print") { pickingPDF = true }
                        .disabled(!dispatcher.isReady)
                } header: {
                    Text("pdf.section")
                } footer: {
                    Text("pdf.footer")
                }
            }

            Section("demos.section") {
                Button("demo.weather") {
                    dispatcher.print(DemoDocuments.weatherAndHoroscope())
                }
                Button("demo.typography") {
                    dispatcher.print(DemoDocuments.typographySampler())
                }
                Button("print.pattern") { dispatcher.printTestPattern() }
                // Sonde des pages de code du firmware 5890: sans objet
                // pour une imprimante qui recoit une image.
                if !dispatcher.isBrother {
                    Button("demo.codePages") {
                        dispatcher.print(DemoDocuments.codePageProbe())
                    }
                }
            }
            .disabled(!dispatcher.isReady)

            // Un travail vide fait avancer le papier de la 5890; une
            // Brother n'en a pas besoin.
            if !dispatcher.isBrother {
                Section {
                    Button("print.clearPaper") {
                        dispatcher.print(PrintDocument())
                    }
                    .disabled(!dispatcher.isReady)
                }
            }
        }
        .navigationTitle("tab.tools")
        .fileImporter(isPresented: $pickingPDF, allowedContentTypes: [.pdf]) { result in
            printPDF(result)
        }
    }

    private var dispatcher: PrintDispatcher {
        PrintDispatcher(setup: setup, transport: transport, brother: brother, options: options)
    }

    private func printQR() {
        guard let element = try? PrintElement.qr(codeContent, printWidth: dispatcher.layoutWidth) else {
            return
        }
        dispatcher.print(PrintDocument(elements: [element]))
    }

    private func printBarcode() {
        // Code 128 accepte tout l'ASCII imprimable, contrairement aux
        // symbologies numeriques.
        guard let element = try? PrintElement.code(
            codeContent, symbology: .code128, printWidth: dispatcher.layoutWidth
        ) else {
            dispatcher.reportError(NSLocalizedString("codes.invalid", comment: ""))
            return
        }
        dispatcher.print(PrintDocument(elements: [element]))
    }

    /// Le fichier choisi n'est lisible que le temps de l'acces securise:
    /// on le copie avant de le confier a la file du SDK.
    private func printPDF(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("pdf")
            do {
                try FileManager.default.copyItem(at: url, to: copy)
                brother.printPDF(at: copy, job: setup.brotherJob)
            } catch {
                brother.reportError(error.localizedDescription)
            }
        case let .failure(error):
            brother.reportError(error.localizedDescription)
        }
    }
}
