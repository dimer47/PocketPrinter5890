import L13BLETransport
import L13Core
import SwiftUI

struct ContentView: View {
    @StateObject private var transport = L13BLETransport()
    @State private var receipt = Receipt.sample
    @State private var density: L13Density = .medium
    @State private var printerWidth: PrinterWidth = .mm58
    @State private var paperMode: PaperMode = .continuous
    @State private var threshold = 128.0
    @State private var ditherMode: DitherMode = .floydSteinberg
    @State private var feedDots = 80.0
    @State private var labelLength = 32.0
    @State private var freeText = "BONJOUR\nCeci est un test de texte natif."
    @State private var textSize = 1
    @State private var textBold = false
    @State private var textAlignment: ESCPOS.Alignment = .left

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 460)
        } detail: {
            HSplitView {
                editor.frame(minWidth: 380)
                previewAndConsole.frame(minWidth: 460)
            }
        }
        .frame(minWidth: 1040, minHeight: 720)
    }

    private var sidebar: some View {
        ScrollView {
            sidebarContent
                .padding(.top, 8)
        }
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("L13 Receipt Printer")
                .font(.title2.weight(.semibold))
            Text("Mini imprimante de poche 58 mm - 384 px, modele A2Y.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if transport.isConnected {
                DeviceStatusBar(
                    battery: transport.batteryPercent,
                    model: transport.deviceModel,
                    firmware: transport.deviceFirmware
                )
            }
            Text(transport.stateText)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Button(transport.isScanning ? "Arreter" : "Rechercher") {
                    transport.isScanning ? transport.stopScan() : transport.startScan()
                }
                .buttonStyle(.borderedProminent)

                Button("Deconnecter") {
                    transport.disconnect()
                }
                .disabled(!transport.isConnected)
            }
            Toggle("Afficher seulement les imprimantes probables", isOn: $transport.showOnlyLikelyPrinters)
            Picker("Canal BLE", selection: $transport.preferredProfileID) {
                Text("Automatique (FF00 d'abord)").tag(L13BLEProfiles.automaticID)
                ForEach(L13BLEProfiles.preferred) { profile in
                    Text(profile.id).tag(profile.id)
                }
            }
            .disabled(transport.isConnected)

            List(transport.devices) { device in
                Button {
                    transport.connect(to: device)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.name)
                        if device.isLikelyL13 {
                            Text("Candidat imprimante")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        Text("\(device.id.uuidString)  \(device.rssi) dBm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 170)

            GroupBox("GATT retenu") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Service: \(transport.selectedService)")
                    Text("RX: \(transport.selectedRX)")
                    Text("TX: \(transport.selectedTX)")
                    Text("Notify: \(transport.selectedNotify)")
                }
                .font(.caption.monospaced())
                .textSelection(.enabled)
            }

            Button("Lire modele / firmware / batterie / papier") {
                transport.readDeviceInformation()
            }
            .disabled(!transport.isConnected)

            Button("Verifier papier seulement") {
                transport.send(L13Command.paperStatus, label: "Verifier papier")
            }
            .disabled(!transport.isConnected)

            printSettings

            Button("Imprimer le ticket") {
                sendReceipt()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!transport.isConnected)

            Button("Imprimer une mire") {
                sendTestPattern()
            }
            .disabled(!transport.isConnected)

            Divider()

            Text("Texte natif (sans rasterisation)")
                .font(.headline)
            TextEditor(text: $freeText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 70)
                .border(Color.secondary.opacity(0.3))
            HStack {
                Picker("", selection: $textAlignment) {
                    ForEach(ESCPOS.Alignment.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .labelsHidden()
                Stepper("Taille \(textSize)", value: $textSize, in: 1...4)
                Toggle("Gras", isOn: $textBold)
            }
            Button("Imprimer ce texte") {
                printer().print(
                    text: freeText,
                    size: textSize,
                    bold: textBold,
                    alignment: textAlignment,
                    options: options()
                )
            }
            .disabled(!transport.isConnected || freeText.isEmpty)

            Divider()

            Button("Demo meteo + horoscope") {
                printer().print(DemoDocuments.weatherAndHoroscope(), options: options())
            }
            .disabled(!transport.isConnected)

            Button("Nuancier typographique") {
                printer().print(DemoDocuments.typographySampler(), options: options())
            }
            .disabled(!transport.isConnected)

            Button("Degager le papier (\(Int(feedDots)) points)") {
                // Le degagement manuel passe par la sequence complete: une
                // commande d'avance envoyee seule est ignoree par le firmware.
                printer().print(PrintDocument(), options: options())
            }
            .disabled(!transport.isConnected)
        }
        .padding()
    }

    private var printSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Largeur", selection: $printerWidth) {
                ForEach(PrinterWidth.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            Picker("Densite", selection: $density) {
                ForEach(L13Density.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            Picker("Papier", selection: $paperMode) {
                ForEach(PaperMode.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            Picker("Tramage", selection: $ditherMode) {
                ForEach(DitherMode.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            Toggle("Controle de flux par credits", isOn: $transport.useCreditFlowControl)
            VStack(alignment: .leading) {
                Text("Seuil noir/blanc \(Int(threshold))")
                Slider(value: $threshold, in: 64...224, step: 1)
                Text("Paquet BLE \(transport.maxChunkSize) octets")
                Slider(value: Binding(
                    get: { Double(transport.maxChunkSize) },
                    set: { transport.maxChunkSize = Int($0) }
                ), in: 20...500, step: 10)
                Text("Degagement papier \(Int(feedDots)) points (~\(Int(Double(feedDots) / 8.0)) mm)")
                Slider(value: $feedDots, in: 0...1200, step: 10)
                if paperMode == .label {
                    Text("Longueur d'etiquette \(Int(labelLength))")
                    Slider(value: $labelLength, in: 8...255, step: 1)
                }
            }
        }
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ticket de test")
                    .font(.title3.weight(.semibold))
                TextField("Commerce", text: $receipt.merchantName)
                TextField("Adresse", text: $receipt.address)
                DatePicker("Date", selection: $receipt.date)

                Text("Articles")
                    .font(.headline)
                ForEach($receipt.items) { $item in
                    HStack {
                        TextField("Article", text: $item.name)
                        Stepper("\(item.quantity)", value: $item.quantity, in: 1...99)
                            .frame(width: 80)
                        DecimalField(value: $item.unitPrice)
                            .frame(width: 80)
                    }
                }
                HStack {
                    Button("Ajouter") {
                        receipt.items.append(ReceiptItem(name: "Article", quantity: 1, unitPrice: 1))
                    }
                    Button("Retirer") {
                        if !receipt.items.isEmpty {
                            receipt.items.removeLast()
                        }
                    }
                    Button("Reinitialiser") {
                        receipt = .sample
                    }
                }

                TextField("Pied de ticket", text: $receipt.footer)
            }
            .padding()
        }
    }

    private var previewAndConsole: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    Text("Apercu monochrome \(printerWidth.pixels) px, longueur variable")
                        .font(.title3.weight(.semibold))
                    ReceiptPreview(receipt: receipt, width: printerWidth.pixels)
                        .frame(width: 384, height: 300)
                        .background(Color.white)
                        .border(Color.black.opacity(0.25))
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            Divider()
            console.frame(height: 230)
        }
    }

    private var console: some View {
        VStack(alignment: .leading) {
            Text("Console hex RX/TX")
                .font(.headline)
            Text(transport.logFileURL.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            List(transport.log) { entry in
                HStack(alignment: .top) {
                    Text(entry.direction.rawValue)
                        .font(.caption.monospaced().weight(.bold))
                        .frame(width: 34, alignment: .leading)
                    Text(entry.label)
                        .font(.caption)
                        .frame(width: 145, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.hex)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        if !entry.decoded.isEmpty {
                            Text(entry.decoded)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding([.horizontal, .top])
    }

    private func printer() -> PocketPrinter {
        PocketPrinter(transport: transport, options: options())
    }

    private func renderer() -> ReceiptRenderer {
        ReceiptRenderer(
            width: printerWidth.pixels,
            threshold: UInt8(threshold),
            ditherMode: ditherMode
        )
    }

    private func options() -> PrintOptions {
        PrintOptions(
            width: printerWidth,
            density: density,
            trailingFeedDots: Int(feedDots),
            paperMode: paperMode,
            labelLength: UInt8(labelLength)
        )
    }

    private func sendReceipt() {
        do {
            let bitmap = try renderer().render(receipt)
            transport.send(PrintJobBuilder.segments(bitmap: bitmap, options: options()))
        } catch {
            transport.recordLocalError("Erreur rendu: \(error.localizedDescription)")
        }
    }

    private func sendTestPattern() {
        do {
            let bitmap = try renderer().testPattern()
            transport.send(PrintJobBuilder.segments(bitmap: bitmap, options: options()))
        } catch {
            transport.recordLocalError("Erreur mire: \(error.localizedDescription)")
        }
    }
}

private struct ReceiptPreview: View {
    let receipt: Receipt
    let width: Int

    var body: some View {
        // On affiche le rendu reel plutot qu'un dessin approche: l'apercu
        // correspond ainsi exactement a ce qui sera imprime.
        Group {
            if let image = renderedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .background(Color.white)
            } else {
                Color.white
            }
        }
    }

    private var renderedImage: NSImage? {
        ReceiptRenderer(width: width).previewImage(receipt)
    }
}

/// Bandeau d'etat: batterie, modele et firmware.
///
/// La batterie est rafraichie automatiquement toutes les 25 secondes par le
/// transport, comme le fait l'application officielle.
private struct DeviceStatusBar: View {
    let battery: Int?
    let model: String?
    let firmware: String?

    var body: some View {
        HStack(spacing: 10) {
            if let battery {
                Image(systemName: symbol(for: battery))
                    .foregroundStyle(color(for: battery))
                    .imageScale(.large)
                Text("\(battery) %")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Batterie...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let model {
                Text(model)
                    .font(.caption.weight(.medium))
            }
            if let firmware {
                Text(firmware)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func symbol(for level: Int) -> String {
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
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

private struct DecimalField: View {
    @Binding var value: Decimal

    var body: some View {
        TextField("Prix", text: Binding(
            get: { "\(value)" },
            set: { value = Decimal(string: $0.replacingOccurrences(of: ",", with: ".")) ?? value }
        ))
        .multilineTextAlignment(.trailing)
    }
}
