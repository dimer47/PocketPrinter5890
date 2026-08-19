import PocketPrinter5890BLE
import PocketPrinter5890Kit
import SwiftUI

struct ContentView: View {
    @StateObject private var transport = PocketPrinter5890BLE()
    @State private var receipt = Receipt.sample
    @State private var density: PrintDensity = .medium
    @State private var printerWidth: PrinterWidth = .mm58
    @State private var paperMode: PaperMode = .continuous
    @State private var threshold = 128.0
    @State private var ditherMode: DitherMode = .floydSteinberg
    @State private var feedDots = 80.0
    @State private var labelLength = 32.0
    @State private var freeText = NSLocalizedString("text.sample", comment: "")
    @State private var textSize = 1
    @State private var textBold = false
    @State private var textAlignment: ESCPOS.Alignment = .left
    @State private var autoShutdown = 15.0
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 420)
        } detail: {
            // En dessous d'un certain seuil, l'editeur et l'apercu ne
            // tiennent plus cote a cote: on bascule alors en onglets plutot
            // que de laisser la fenetre pousser la barre laterale hors de
            // l'ecran.
            GeometryReader { geometry in
                if geometry.size.width < 760 {
                    TabView {
                        editor
                            .tabItem { Text("tab.editor") }
                        previewAndConsole
                            .tabItem { Text("tab.preview") }
                    }
                    .padding(.top, 4)
                } else {
                    HSplitView {
                        editor.frame(minWidth: 300)
                        previewAndConsole.frame(minWidth: 320)
                    }
                }
            }
        }
        // `.automatic` laisse macOS escamoter la barre laterale quand la
        // fenetre devient etroite, au lieu de la conserver a tout prix.
        .navigationSplitViewStyle(.automatic)
        .frame(minWidth: 480, idealWidth: 1200, minHeight: 480, idealHeight: 800)
    }

    private var sidebar: some View {
        ScrollView {
            sidebarContent
                .padding(.top, 8)
        }
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("app.title")
                .font(.title2.weight(.semibold))
            Text("app.subtitle")
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
                Button(transport.isScanning ? "scan.stop" : "scan.start") {
                    transport.isScanning ? transport.stopScan() : transport.startScan()
                }
                .buttonStyle(.borderedProminent)

                Button("device.disconnect") {
                    transport.disconnect()
                }
                .disabled(!transport.isConnected)
            }
            Toggle("device.filter", isOn: $transport.showOnlyLikelyPrinters)
            Picker("ble.channel", selection: $transport.preferredProfileID) {
                Text("ble.automatic").tag(PrinterBLEProfiles.automaticID)
                ForEach(PrinterBLEProfiles.preferred) { profile in
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
                            Text("device.candidate")
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

            GroupBox("gatt.title") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Service: \(transport.selectedService)")
                    Text("RX: \(transport.selectedRX)")
                    Text("TX: \(transport.selectedTX)")
                    Text("Notify: \(transport.selectedNotify)")
                }
                .font(.caption.monospaced())
                .textSelection(.enabled)
            }

            Button("info.read") {
                transport.readDeviceInformation()
            }
            .disabled(!transport.isConnected)

            HStack {
                Text(autoShutdown == 0
                     ? NSLocalizedString("shutdown.disabled", comment: "")
                     : String(format: NSLocalizedString("shutdown.delay", comment: ""), Int(autoShutdown)))
                Spacer()
                Button("shutdown.apply") {
                    printer().setAutoShutdown(minutes: Int(autoShutdown))
                }
                .disabled(!transport.isConnected)
            }
            Slider(value: $autoShutdown, in: 0...240, step: 5)
                .disabled(!transport.isConnected)
            Text("shutdown.hint")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("settings.read") {
                printer().readSettings()
            }
            .disabled(!transport.isConnected)

            Button("paper.check") {
                transport.send(PrinterCommand.paperStatus, label: "Verifier papier")
            }
            .disabled(!transport.isConnected)

            printSettings

            Button("print.receipt") {
                sendReceipt()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!transport.isConnected)

            Button("print.pattern") {
                sendTestPattern()
            }
            .disabled(!transport.isConnected)

            Divider()

            Text("text.native")
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
                Stepper(String(format: NSLocalizedString("text.size", comment: ""), textSize), value: $textSize, in: 1...4)
                Toggle("text.bold", isOn: $textBold)
            }
            Button("print.text") {
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

            Button("demo.weather") {
                printer().print(DemoDocuments.weatherAndHoroscope(), options: options())
            }
            .disabled(!transport.isConnected)

            Button("demo.typography") {
                printer().print(DemoDocuments.typographySampler(), options: options())
            }
            .disabled(!transport.isConnected)

            Button(String(format: NSLocalizedString("print.clearPaper", comment: ""), Int(feedDots))) {
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
            Picker("settings.width", selection: $printerWidth) {
                ForEach(PrinterWidth.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            Picker("settings.density", selection: $density) {
                ForEach(PrintDensity.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            Picker("settings.paper", selection: $paperMode) {
                ForEach(PaperMode.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            Picker("settings.dither", selection: $ditherMode) {
                ForEach(DitherMode.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            Toggle("settings.creditFlow", isOn: $transport.useCreditFlowControl)
            VStack(alignment: .leading) {
                Text(String(format: NSLocalizedString("settings.threshold", comment: ""), Int(threshold)))
                Slider(value: $threshold, in: 64...224, step: 1)
                Text(String(format: NSLocalizedString("settings.packet", comment: ""), transport.maxChunkSize))
                Slider(value: Binding(
                    get: { Double(transport.maxChunkSize) },
                    set: { transport.maxChunkSize = Int($0) }
                ), in: 20...500, step: 10)
                Text(String(format: NSLocalizedString("settings.feed", comment: ""), Int(feedDots), Int(Double(feedDots) / 8.0)))
                Slider(value: $feedDots, in: 0...1200, step: 10)
                if paperMode == .label {
                    Text(String(format: NSLocalizedString("settings.labelLength", comment: ""), Int(labelLength)))
                    Slider(value: $labelLength, in: 8...255, step: 1)
                }
            }
        }
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("editor.title")
                    .font(.title3.weight(.semibold))
                TextField("editor.merchant", text: $receipt.merchantName)
                TextField("editor.address", text: $receipt.address)
                DatePicker("editor.date", selection: $receipt.date)

                Text("editor.items")
                    .font(.headline)
                ForEach($receipt.items) { $item in
                    HStack {
                        TextField("editor.item", text: $item.name)
                        Stepper("\(item.quantity)", value: $item.quantity, in: 1...99)
                            .frame(width: 80)
                        DecimalField(value: $item.unitPrice)
                            .frame(width: 80)
                    }
                }
                HStack {
                    Button("editor.add") {
                        receipt.items.append(ReceiptItem(name: "editor.item", quantity: 1, unitPrice: 1))
                    }
                    Button("editor.remove") {
                        if !receipt.items.isEmpty {
                            receipt.items.removeLast()
                        }
                    }
                    Button("editor.reset") {
                        receipt = .sample
                    }
                }

                TextField("editor.footer", text: $receipt.footer)
            }
            .padding()
        }
    }

    private var previewAndConsole: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    Text(String(format: NSLocalizedString("preview.title", comment: ""), printerWidth.pixels))
                        .font(.title3.weight(.semibold))
                    // Largeur souple: l'apercu se reduit sur un ecran etroit
                    // au lieu d'imposer 384 px a toute la fenetre.
                    ReceiptPreview(receipt: receipt, width: printerWidth.pixels)
                        .frame(maxWidth: 384)
                        .frame(height: 300)
                        .background(Color.white)
                        .border(Color.black.opacity(0.25))
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            Divider()
            console.frame(minHeight: 140, maxHeight: 230)
        }
    }

    private var console: some View {
        VStack(alignment: .leading) {
            Text("console.title")
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
            transport.recordLocalError(String(format: NSLocalizedString("error.render", comment: ""), error.localizedDescription))
        }
    }

    private func sendTestPattern() {
        do {
            let bitmap = try renderer().testPattern()
            transport.send(PrintJobBuilder.segments(bitmap: bitmap, options: options()))
        } catch {
            transport.recordLocalError(String(format: NSLocalizedString("error.pattern", comment: ""), error.localizedDescription))
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
        guard let cgImage = try? ReceiptRenderer(width: width).previewImage(receipt) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
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
                Text("battery.loading")
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
        TextField("editor.price", text: Binding(
            get: { "\(value)" },
            set: { value = Decimal(string: $0.replacingOccurrences(of: ",", with: ".")) ?? value }
        ))
        .multilineTextAlignment(.trailing)
    }
}
