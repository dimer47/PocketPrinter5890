import PocketPrinter5890Kit
import SwiftUI

// Etapes de configuration, dans l'ordre: imprimante, papier, coupe.
// Le papier propose depend toujours de l'imprimante choisie.

// MARK: - 1. Imprimante

struct PrinterChoiceSection: View {
    @ObservedObject var setup: PrinterSetup

    var body: some View {
        Section {
            Picker("printer.brand", selection: $setup.brand) {
                Text("printer.brand.pocket").tag(PrinterBrand.pocket5890)
                Text("printer.brand.brother").tag(PrinterBrand.brother)
            }
            .pickerStyle(.segmented)

            if setup.brand == .brother {
                NavigationLink(destination: BrotherModelPicker(selection: $setup.brotherModel)) {
                    HStack {
                        Text("printer.model")
                        Spacer()
                        Text(setup.brotherModel.title)
                            .foregroundColor(.secondary)
                    }
                }
                ConnectionBadges(model: setup.brotherModel)
            }
        } header: {
            Text("printer.step1")
        } footer: {
            Text(LocalizedStringKey(setup.brand == .pocket5890 ? "printer.pocket.detail" : "printer.brother.detail"))
        }
    }
}

/// Interfaces documentees pour le modele, et celles que l'application gere.
struct ConnectionBadges: View {
    let model: BrotherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ForEach(BrotherConnection.allCases) { connection in
                    if model.connections.contains(connection) {
                        Text(connection.title)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(connection == .ble ? Color.blue.opacity(0.18)
                                                                          : Color.secondary.opacity(0.15)))
                    }
                }
            }
            if model.appConnections.isEmpty {
                Text("printer.noIOSConnection")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if !model.supportsBLE {
                Text("printer.noBLE")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}

struct BrotherModelPicker: View {
    @Binding var selection: BrotherModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var onlyBLE = false

    var body: some View {
        List {
            Toggle("printer.onlyBLE", isOn: $onlyBLE)
            ForEach(BrotherSeries.allCases) { series in
                let models = filtered(series)
                if !models.isEmpty {
                    Section(series.title) {
                        ForEach(models) { model in
                            Button {
                                selection = model
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.title).foregroundColor(.primary)
                                        Text(model.connections.isEmpty
                                             ? NSLocalizedString("printer.connections.none", comment: "")
                                             : model.connections.map(\.title).sorted().joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if model == selection {
                                        Image(systemName: "checkmark").foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("printer.model")
    }

    private func filtered(_ series: BrotherSeries) -> [BrotherModel] {
        BrotherModel.allCases.filter { model in
            model.series == series
                && (!onlyBLE || model.supportsBLE)
                && (query.isEmpty || model.rawValue.localizedCaseInsensitiveContains(query))
        }
    }
}

// MARK: - 2. Papier

struct PaperChoiceSection: View {
    @ObservedObject var setup: PrinterSetup
    @ObservedObject var brother: BrotherPrinterService
    @Binding var options: PrintOptions

    var body: some View {
        Section {
            if setup.brand == .pocket5890 {
                Picker("settings.width", selection: $options.width) {
                    ForEach(PrinterWidth.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                Picker("settings.paper", selection: $options.paperMode) {
                    ForEach(PaperMode.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
            } else {
                brotherPaper
            }
        } header: {
            Text("paper.step2")
        }
    }

    @ViewBuilder
    private var brotherPaper: some View {
        let model = setup.brotherModel
        switch model.series.paperSource {
        case .customPaper:
            CustomPaperEditor(model: model, media: $setup.brotherMedia)
        case .qlLabel, .ptTape:
            Picker("paper.label", selection: labelBinding) {
                ForEach(brother.supportedLabels(for: model)) { label in
                    Text(label.title).tag(label.index)
                }
            }
        case .pjSheet:
            Picker("paper.sheet", selection: sheetBinding) {
                ForEach(BrotherSheet.allCases) { sheet in
                    Text(sheet.title).tag(sheet)
                }
            }
        case .fixedByModel:
            Text("paper.fixed").foregroundColor(.secondary)
        }
    }

    private var labelBinding: Binding<Int> {
        Binding(
            get: {
                switch setup.brotherMedia {
                case let .qlLabel(index), let .ptTape(index): return index
                default: return 0
                }
            },
            set: { index in
                setup.brotherMedia = setup.brotherModel.series == .ql ? .qlLabel(index) : .ptTape(index)
            }
        )
    }

    private var sheetBinding: Binding<BrotherSheet> {
        Binding(
            get: {
                if case let .sheet(sheet) = setup.brotherMedia { return sheet }
                return .a4
            },
            set: { setup.brotherMedia = .sheet($0) }
        )
    }
}

/// Rouleau continu, etiquettes predecoupees ou rouleau a marque noire,
/// pour les TD et RJ.
struct CustomPaperEditor: View {
    let model: BrotherModel
    @Binding var media: BrotherMedia

    private static let customID = "custom"

    var body: some View {
        Picker("paper.preset", selection: presetBinding) {
            ForEach(model.paperPresets) { preset in
                Text(title(for: preset)).tag(preset.id)
            }
            Text("paper.custom").tag(Self.customID)
        }

        Picker("paper.kind", selection: binding(\.kind)) {
            Text("paper.kind.roll").tag(BrotherPaper.Kind.roll)
            Text("paper.kind.dieCut").tag(BrotherPaper.Kind.dieCut)
            Text("paper.kind.markRoll").tag(BrotherPaper.Kind.markRoll)
        }
        .pickerStyle(.segmented)

        Stepper(value: binding(\.widthMM), in: 10...model.maxPaperWidthMM, step: 1) {
            Text(String(format: NSLocalizedString("paper.width", comment: ""), paper.widthMM))
        }
        if paper.kind.hasFixedLength {
            Stepper(value: binding(\.lengthMM), in: 10...1000, step: 1) {
                Text(String(format: NSLocalizedString("paper.length", comment: ""), paper.lengthMM))
            }
        }
        if paper.kind == .dieCut {
            Stepper(value: binding(\.gapMM), in: 0...20, step: 0.5) {
                Text(String(format: NSLocalizedString("paper.gap", comment: ""), paper.gapMM))
            }
        }
        if paper.kind == .markRoll {
            Stepper(value: binding(\.markOffsetMM), in: 0...max(0, paper.lengthMM), step: 0.5) {
                Text(String(format: NSLocalizedString("paper.markOffset", comment: ""), paper.markOffsetMM))
            }
            Stepper(value: binding(\.markLengthMM), in: 1...20, step: 0.5) {
                Text(String(format: NSLocalizedString("paper.markLength", comment: ""), paper.markLengthMM))
            }
            Text("paper.markRoll.hint")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        Stepper(value: binding(\.marginMM), in: 0...10, step: 0.5) {
            Text(String(format: NSLocalizedString("paper.margin", comment: ""), paper.marginMM))
        }
    }

    private var paper: BrotherPaper {
        if case let .custom(paper) = media { return paper }
        return model.paperPresets.first ?? .roll(widthMM: 58)
    }

    private func title(for paper: BrotherPaper) -> String {
        switch paper.kind {
        case .roll:
            return String(format: NSLocalizedString("paper.roll.title", comment: ""), paper.widthMM)
        case .dieCut:
            return String(format: NSLocalizedString("paper.dieCut.title", comment: ""),
                          paper.widthMM, paper.lengthMM)
        case .markRoll:
            return String(format: NSLocalizedString("paper.markRoll.title", comment: ""),
                          paper.widthMM, paper.lengthMM)
        }
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: { model.paperPresets.contains(paper) ? paper.id : Self.customID },
            set: { id in
                if let preset = model.paperPresets.first(where: { $0.id == id }) {
                    media = .custom(preset)
                }
            }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<BrotherPaper, Value>) -> Binding<Value> {
        Binding(
            get: { paper[keyPath: keyPath] },
            set: { value in
                var updated = paper
                updated[keyPath: keyPath] = value
                // En passant d'un rouleau continu a un papier de longueur
                // fixe, il faut des valeurs de depart plausibles.
                if updated.kind.hasFixedLength, updated.lengthMM <= 0 {
                    updated.lengthMM = updated.widthMM
                }
                if updated.kind == .dieCut, updated.gapMM <= 0 {
                    updated.gapMM = 3
                }
                if updated.kind == .markRoll, updated.markLengthMM <= 0 {
                    updated.markLengthMM = 3
                }
                updated.markOffsetMM = min(updated.markOffsetMM, updated.lengthMM)
                media = .custom(updated)
            }
        )
    }
}

// MARK: - 3. Coupe et copies

struct BrotherCutSection: View {
    @ObservedObject var setup: PrinterSetup

    var body: some View {
        let cutter = setup.brotherModel.series.cutter
        Section {
            if cutter.isControllable {
                Toggle("cut.auto", isOn: $setup.cut.autoCut)
                if setup.cut.autoCut {
                    Stepper(value: $setup.cut.cutEveryPages, in: 1...255) {
                        Text(String(format: NSLocalizedString("cut.every", comment: ""),
                                    setup.cut.cutEveryPages))
                    }
                }
                if cutter.supportsCutAtEnd {
                    Toggle("cut.atEnd", isOn: $setup.cut.cutAtEnd)
                }
            }
            Stepper(value: $setup.copies, in: 1...99) {
                Text(String(format: NSLocalizedString("print.copies", comment: ""), setup.copies))
            }
        } header: {
            Text("cut.step3")
        } footer: {
            Text(footer(for: cutter))
        }
    }

    private func footer(for cutter: BrotherCutterSupport) -> LocalizedStringKey {
        switch cutter {
        case .optionalUnit: return "cut.footer.optional"
        case .builtIn: return "cut.footer.builtIn"
        case .modelDependent: return "cut.footer.modelDependent"
        case .none: return "cut.footer.none"
        }
    }
}

// MARK: - Connexion Brother

struct BrotherConnectionSections: View {
    @ObservedObject var setup: PrinterSetup
    @ObservedObject var brother: BrotherPrinterService
    @State private var connection: BrotherConnection = .ble
    @State private var manualAddress = ""

    var body: some View {
        let model = setup.brotherModel

        Section {
            if !BrotherPrinterService.isSDKAvailable {
                Label("brother.sdk.missing", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
            }

            if model.appConnections.count > 1 {
                Picker("brother.connection", selection: $connection) {
                    ForEach(model.appConnections) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if model.appConnections.isEmpty {
                Text("printer.noIOSConnection").foregroundColor(.secondary)
            } else {
                HStack {
                    Button(brother.activity == .searching ? "scan.stop" : "scan.start") {
                        if brother.activity == .searching {
                            brother.cancelSearch()
                        } else {
                            brother.search(effectiveConnection(for: model))
                        }
                    }
                    .disabled(brother.activity != .idle && brother.activity != .searching)
                    if brother.activity != .idle {
                        Spacer()
                        ProgressView()
                    }
                }
            }

            if effectiveConnection(for: model) == .wifi {
                HStack {
                    TextField("brother.ip", text: $manualAddress)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button("brother.ip.use") { brother.useAddress(manualAddress) }
                        .disabled(manualAddress.isEmpty)
                }
            }

            Text(brother.status)
                .font(.callout)
                .foregroundColor(brother.statusIsError ? .red : .secondary)
        } header: {
            Text("brother.connection.title")
        }

        Section("devices.found") {
            if brother.found.isEmpty {
                Text("brother.found.none").foregroundColor(.secondary)
            }
            ForEach(brother.found) { printer in
                Button {
                    brother.select(printer)
                    // Le modele detecte prime: c'est lui qui fixe le papier
                    // et les reglages acceptes.
                    if let detected = printer.detectedModel { setup.brotherModel = detected }
                } label: {
                    TargetRow(printer: printer, isSelected: printer == brother.target)
                }
            }
        }

        if let target = brother.target {
            Section("brother.target") {
                TargetRow(printer: target, isSelected: true)
                if let detected = target.detectedModel, detected != model {
                    Text(String(format: NSLocalizedString("brother.model.mismatch", comment: ""),
                                detected.title, model.title))
                        .font(.caption)
                        .foregroundColor(.orange)
                    Button("brother.model.useDetected") { setup.brotherModel = detected }
                }
                Button("brother.status.check") { brother.checkStatus(model: model) }
                    .disabled(brother.activity != .idle)
                Button("brother.target.forget", role: .destructive) { brother.target = nil }
            }
        }

        if !brother.events.isEmpty {
            Section("brother.log") {
                ForEach(brother.events.suffix(12).reversed()) { event in
                    Text(event.text)
                        .font(.caption)
                        .foregroundColor(event.isError ? .red : .secondary)
                }
            }
        }
    }

    /// La recherche se fait sur l'interface choisie, ramenee a une
    /// interface reellement disponible sur le modele.
    private func effectiveConnection(for model: BrotherModel) -> BrotherConnection {
        model.appConnections.contains(connection) ? connection : (model.appConnections.first ?? .ble)
    }
}

private struct TargetRow: View {
    let printer: BrotherTarget
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(printer.modelName.isEmpty ? printer.address : printer.modelName)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                Text("\(printer.connection.title) · \(printer.address)")
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            }
        }
    }
}
