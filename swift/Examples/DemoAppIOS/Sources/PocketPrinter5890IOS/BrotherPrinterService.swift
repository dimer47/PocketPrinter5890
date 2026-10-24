import CoreGraphics
import Foundation
import PocketPrinter5890Kit
#if canImport(BRLMPrinterKit)
import BRLMPrinterKit
#endif

/// Imprimante Brother trouvee par une recherche, ou saisie a la main.
struct BrotherTarget: Codable, Hashable, Identifiable {
    let connection: BrotherConnection
    /// Nom local BLE annonce, ou adresse IP en Wi-Fi.
    let address: String
    /// Nom renvoye par le SDK, par exemple « Brother TD-4550DNWB ». Vide
    /// pour une adresse saisie a la main.
    let modelName: String

    var id: String { connection.rawValue + "|" + address }

    var detectedModel: BrotherModel? { BrotherModel.matching(advertisedName: modelName) }
}

/// Communication avec les imprimantes Brother via le Brother Print SDK.
///
/// Toutes les fonctions du SDK sont bloquantes (recherche, ouverture du
/// canal, impression): elles s'executent sur une file dediee, et seul le
/// resultat revient sur le fil principal.
///
/// Le SDK n'est pas livre avec ce depot. Sans lui, l'application compile
/// quand meme: le service indique alors qu'il manque, au lieu d'echouer.
@MainActor
final class BrotherPrinterService: ObservableObject {
    enum Activity: Equatable {
        case idle
        case searching
        case connecting
        case printing
    }

    struct Event: Identifiable {
        let id = UUID()
        let date = Date()
        let text: String
        let isError: Bool
    }

    static let isSDKAvailable: Bool = {
        #if canImport(BRLMPrinterKit)
        return true
        #else
        return false
        #endif
    }()

    @Published private(set) var activity: Activity = .idle
    @Published private(set) var found: [BrotherTarget] = []
    /// Dernier message d'etat, affiche sous les boutons.
    @Published private(set) var status: String
    @Published private(set) var statusIsError = false
    @Published private(set) var events: [Event] = []
    /// Imprimante retenue. Conservee: le SDK n'a pas besoin d'une nouvelle
    /// recherche quand on connait deja son nom local ou son adresse.
    @Published var target: BrotherTarget? = nil {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(target), forKey: Self.targetKey)
        }
    }

    private static let targetKey = "printer.brother.target"
    private let queue = DispatchQueue(label: "PocketPrinter5890.brother", qos: .userInitiated)

    init() {
        status = Self.isSDKAvailable
            ? NSLocalizedString("brother.status.ready", comment: "")
            : NSLocalizedString("brother.sdk.missing", comment: "")
        statusIsError = !Self.isSDKAvailable
        if let data = UserDefaults.standard.data(forKey: Self.targetKey) {
            target = try? JSONDecoder().decode(BrotherTarget.self, from: data)
        }
    }

    var canPrint: Bool {
        Self.isSDKAvailable && target != nil && activity == .idle
    }

    // MARK: - Recherche

    /// Recherche les imprimantes Brother proches pendant `duration` secondes.
    func search(_ connection: BrotherConnection, duration: TimeInterval = 10) {
        guard activity == .idle else { return }
        guard Self.isSDKAvailable else {
            report(NSLocalizedString("brother.sdk.missing", comment: ""), isError: true)
            return
        }
        found.removeAll()
        activity = .searching
        report(String(format: NSLocalizedString("brother.search.running", comment: ""),
                      connection.title, Int(duration)))

        #if canImport(BRLMPrinterKit)
        queue.async { [weak self] in
            let onFound: (BRLMChannel) -> Void = { channel in
                let modelName = channel.extraInfo?.value(forKey: BRLMChannelExtraInfoKeyModelName) as? String ?? ""
                let printer = BrotherTarget(connection: connection, address: channel.channelInfo,
                                            modelName: modelName)
                Task { @MainActor in self?.add(printer) }
            }
            let result: BRLMPrinterSearchResult
            switch connection {
            case .ble:
                let option = BRLMBLESearchOption()
                option.searchDuration = duration
                result = BRLMPrinterSearcher.startBLESearch(option, callback: onFound)
            default:
                let option = BRLMNetworkSearchOption()
                option.searchDuration = duration
                result = BRLMPrinterSearcher.startNetworkSearch(option, callback: onFound)
            }
            let message = BrotherSDKBridge.searchMessage(result.error.code)
            Task { @MainActor in self?.finishSearch(errorMessage: message) }
        }
        #endif
    }

    func cancelSearch() {
        #if canImport(BRLMPrinterKit)
        queue.async {
            BRLMPrinterSearcher.cancelBLESearch()
            BRLMPrinterSearcher.cancelNetworkSearch()
        }
        #endif
    }

    /// Wi-Fi: adresse connue, sans recherche.
    func useAddress(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        target = BrotherTarget(connection: .wifi, address: trimmed, modelName: "")
        report(String(format: NSLocalizedString("brother.target.selected", comment: ""), trimmed))
    }

    func select(_ printer: BrotherTarget) {
        target = printer
        report(String(format: NSLocalizedString("brother.target.selected", comment: ""),
                      printer.modelName.isEmpty ? printer.address : printer.modelName))
    }

    private func add(_ printer: BrotherTarget) {
        guard !found.contains(where: { $0.id == printer.id }) else { return }
        found.append(printer)
        log(String(format: NSLocalizedString("brother.search.found", comment: ""),
                   printer.modelName.isEmpty ? "?" : printer.modelName, printer.address))
    }

    private func finishSearch(errorMessage: String?) {
        activity = .idle
        if let errorMessage {
            report(errorMessage, isError: true)
        } else if found.isEmpty {
            report(NSLocalizedString("brother.search.none", comment: ""), isError: true)
        } else {
            report(String(format: NSLocalizedString("brother.search.done", comment: ""), found.count))
        }
    }

    // MARK: - Etat de l'imprimante

    /// Ouvre le canal, lit l'etat, referme. Verifie la connexion sans imprimer.
    func checkStatus(model: BrotherModel) {
        guard activity == .idle, let target else { return }
        guard Self.isSDKAvailable else {
            report(NSLocalizedString("brother.sdk.missing", comment: ""), isError: true)
            return
        }
        activity = .connecting
        report(String(format: NSLocalizedString("brother.connecting", comment: ""), target.address))

        #if canImport(BRLMPrinterKit)
        queue.async { [weak self] in
            let outcome = BrotherSDKBridge.readStatus(target: target)
            Task { @MainActor in
                self?.activity = .idle
                self?.report(outcome.message, isError: outcome.isError)
            }
        }
        #endif
    }

    // MARK: - Impression

    /// Imprime une image produite par `render` a l'echelle demandee.
    ///
    /// Le rendu se fait sur la file du SDK, pas sur le fil principal: un
    /// ticket dessine en 300 dpi sur 4 pouces represente plusieurs
    /// millions de pixels.
    func print(job: BrotherJob, render: @escaping @Sendable (_ scale: CGFloat) throws -> CGImage) {
        guard activity == .idle else { return }
        guard Self.isSDKAvailable else {
            report(NSLocalizedString("brother.sdk.missing", comment: ""), isError: true)
            return
        }
        guard let target else {
            report(NSLocalizedString("brother.target.none", comment: ""), isError: true)
            return
        }
        activity = .printing
        report(String(format: NSLocalizedString("brother.printing", comment: ""), job.model.title))
        if let detected = target.detectedModel, detected != job.model {
            log(String(format: NSLocalizedString("brother.model.mismatch", comment: ""),
                       detected.title, job.model.title), isError: true)
        }

        #if canImport(BRLMPrinterKit)
        queue.async { [weak self] in
            let outcome: BrotherSDKBridge.Outcome
            do {
                let scale = BrotherSDKBridge.renderScale(for: job)
                let image = try render(scale)
                outcome = BrotherSDKBridge.print(image: image, job: job, target: target)
            } catch {
                outcome = .init(message: String(format: NSLocalizedString("error.render", comment: ""),
                                                error.localizedDescription), isError: true)
            }
            Task { @MainActor in
                self?.activity = .idle
                for warning in outcome.warnings { self?.log(warning) }
                self?.report(outcome.message, isError: outcome.isError)
            }
        }
        #endif
    }

    /// Liste des etiquettes QL ou rubans PT acceptes par le modele, selon le
    /// SDK. Sans SDK, toute la liste est proposee.
    func supportedLabels(for model: BrotherModel) -> [BrotherLabelSize] {
        switch model.series.paperSource {
        case .qlLabel:
            #if canImport(BRLMPrinterKit)
            let spec = BRLMPrinterModelSpec(printerModel: BrotherSDKBridge.sdkModel(model))
            let indices = Set(spec.supportedQLLabels.map(\.intValue))
            let labels = BrotherLabelSize.ql.filter { indices.contains($0.index) }
            return labels.isEmpty ? BrotherLabelSize.ql : labels
            #else
            return BrotherLabelSize.ql
            #endif
        case .ptTape:
            #if canImport(BRLMPrinterKit)
            let spec = BRLMPrinterModelSpec(printerModel: BrotherSDKBridge.sdkModel(model))
            let indices = Set(spec.supportedPTLabels.map(\.intValue))
            let labels = BrotherLabelSize.pt.filter { indices.contains($0.index) }
            return labels.isEmpty ? BrotherLabelSize.pt : labels
            #else
            return BrotherLabelSize.pt
            #endif
        default:
            return []
        }
    }

    // MARK: - Journal

    /// Erreur survenue avant l'envoi (rendu, contenu invalide).
    func reportError(_ text: String) {
        report(text, isError: true)
    }

    private func report(_ text: String, isError: Bool = false) {
        status = text
        statusIsError = isError
        log(text, isError: isError)
    }

    private func log(_ text: String, isError: Bool = false) {
        events.append(Event(text: text, isError: isError))
        if events.count > 50 { events.removeFirst(events.count - 50) }
    }
}

#if canImport(BRLMPrinterKit)
/// Traduction entre le modele de l'application et le Brother Print SDK.
///
/// Les noms d'API, de cas et de proprietes suivent les en-tetes du SDK 4.13
/// et l'application d'exemple Swift fournie par Brother.
enum BrotherSDKBridge {
    struct Outcome {
        var message: String
        var isError: Bool
        var warnings: [String] = []
    }

    // MARK: Canal

    static func channel(for target: BrotherTarget) -> BRLMChannel? {
        switch target.connection {
        case .ble: return BRLMChannel(bleLocalName: target.address)
        case .wifi: return BRLMChannel(wifiIPAddress: target.address)
        case .bluetoothClassic: return nil
        }
    }

    /// Ouvre le canal, execute `body`, referme toujours le canal.
    private static func withDriver(
        target: BrotherTarget,
        _ body: (BRLMPrinterDriver) -> Outcome
    ) -> Outcome {
        guard let channel = channel(for: target) else {
            return Outcome(message: NSLocalizedString("brother.error.unsupportedChannel", comment: ""),
                           isError: true)
        }
        let generated = BRLMPrinterDriverGenerator.open(channel)
        guard generated.error.code == .noError, let driver = generated.driver else {
            return Outcome(message: openChannelMessage(generated.error.code), isError: true)
        }
        defer { driver.closeChannel() }
        return body(driver)
    }

    // MARK: Etat

    static func readStatus(target: BrotherTarget) -> Outcome {
        withDriver(target: target) { driver in
            let result = driver.getPrinterStatus()
            guard result.error.code == .noError, let status = result.status else {
                return Outcome(message: NSLocalizedString("brother.status.unreadable", comment: ""),
                               isError: true)
            }
            var parts = [statusMessage(status.errorCode)]
            if let battery = status.batteryStatus, battery.chargeLevel.max > 0 {
                parts.append(String(format: NSLocalizedString("brother.status.battery", comment: ""),
                                    battery.chargeLevel.current, battery.chargeLevel.max))
            }
            if let media = status.mediaInfo, media.width_mm > 0 {
                parts.append(String(format: NSLocalizedString("brother.status.media", comment: ""),
                                    Int(media.width_mm)))
            }
            return Outcome(message: parts.joined(separator: " · "),
                           isError: status.errorCode != .noError)
        }
    }

    // MARK: Impression

    static func print(image: CGImage, job: BrotherJob, target: BrotherTarget) -> Outcome {
        guard let settings = settings(for: job) else {
            return Outcome(message: NSLocalizedString("brother.error.settings", comment: ""), isError: true)
        }

        // Le SDK sait dire avant l'envoi si un reglage est incoherent avec
        // le modele (papier trop large, coupe non geree...).
        let report = BRLMValidatePrintSettings.validate(settings)
        let errors = report.issues.filter { $0.rank == .error }.map(\.message)
        let warnings = report.issues.filter { $0.rank != .error }.map(\.message)
        if !errors.isEmpty {
            return Outcome(message: errors.joined(separator: "\n"), isError: true, warnings: warnings)
        }

        var outcome = withDriver(target: target) { driver in
            let error = driver.printImage(with: image, settings: settings)
            if error.code == .noError {
                return Outcome(message: NSLocalizedString("brother.print.done", comment: ""), isError: false)
            }
            return Outcome(message: printMessage(error.code), isError: true)
        }
        outcome.warnings = warnings
        return outcome
    }

    /// Echelle de rendu pour que l'image arrive a la resolution de la tete.
    ///
    /// Les documents sont mis en page sur 384 points, comme pour la 5890.
    static func renderScale(for job: BrotherJob) -> CGFloat {
        let spec = BRLMPrinterModelSpec(printerModel: sdkModel(job.model))
        let dpi = spec.xdpi > 0 ? spec.xdpi : 203
        let pixels = job.media.printableWidthMM / 25.4 * dpi
        return CGFloat(min(8, max(1, pixels / Double(MonochromeBitmap.nativeWidth))))
    }

    static func settings(for job: BrotherJob) -> BRLMPrintSettingsProtocol? {
        let model = sdkModel(job.model)
        switch job.model.series {
        case .td:
            guard let settings = BRLMTDPrintSettings(defaultPrintSettingsWith: model) else { return nil }
            if case let .custom(paper) = job.media {
                settings.customPaperSize = customPaperSize(paper)
            }
            // autoCut: coupe apres chaque page (ou toutes les N pages).
            // cutAtEnd: coupe apres la derniere page du travail.
            // Ces reglages ne font rien si le massicot n'est pas installe.
            settings.autoCut = job.cut.autoCut
            settings.autoCutForEachPageCount = job.cut.clampedCutEveryPages
            settings.cutAtEnd = job.cut.cutAtEnd
            applyImageDefaults(settings, copies: job.copies)
            return settings

        case .rj:
            guard let settings = BRLMRJPrintSettings(defaultPrintSettingsWith: model) else { return nil }
            if case let .custom(paper) = job.media {
                settings.customPaperSize = customPaperSize(paper)
            }
            applyImageDefaults(settings, copies: job.copies)
            return settings

        case .ql:
            guard let settings = BRLMQLPrintSettings(defaultPrintSettingsWith: model) else { return nil }
            if case let .qlLabel(index) = job.media,
               let labelSize = BRLMQLPrintSettingsLabelSize(rawValue: index) {
                settings.labelSize = labelSize
            }
            settings.autoCut = job.cut.autoCut
            settings.autoCutForEachPageCount = job.cut.clampedCutEveryPages
            settings.cutAtEnd = job.cut.cutAtEnd
            applyImageDefaults(settings, copies: job.copies)
            return settings

        case .pt:
            guard let settings = BRLMPTPrintSettings(defaultPrintSettingsWith: model) else { return nil }
            if case let .ptTape(index) = job.media,
               let labelSize = BRLMPTPrintSettingsLabelSize(rawValue: index) {
                settings.labelSize = labelSize
            }
            settings.autoCut = job.cut.autoCut
            settings.autoCutForEachPageCount = job.cut.clampedCutEveryPages
            applyImageDefaults(settings, copies: job.copies)
            return settings

        case .pj:
            guard let settings = BRLMPJPrintSettings(defaultPrintSettingsWith: model) else { return nil }
            if case let .sheet(sheet) = job.media {
                settings.paperSize = BRLMPJPrintSettingsPaperSize(paperSizeStandard: paperSizeStandard(sheet))
            }
            applyImageDefaults(settings, copies: job.copies)
            return settings

        case .mw:
            guard let settings = BRLMMWPrintSettings(defaultPrintSettingsWith: model) else { return nil }
            applyImageDefaults(settings, copies: job.copies)
            return settings
        }
    }

    private static func applyImageDefaults(_ settings: BRLMPrintImageSettings, copies: Int) {
        settings.numCopies = UInt(max(1, copies))
        // L'image est mise a la largeur du papier en gardant ses proportions.
        settings.scaleMode = .fitPageAspect
        settings.hAlignment = .center
        settings.vAlignment = .center
        // Texte et codes: un seuil donne des traits nets, sans trame.
        settings.halftone = .threshold
    }

    private static func customPaperSize(_ paper: BrotherPaper) -> BRLMCustomPaperSize {
        let margin = CGFloat(paper.marginMM)
        let margins = BRLMCustomPaperSizeMargins(top: margin, left: margin, bottom: margin, right: margin)
        switch paper.kind {
        case .roll:
            return BRLMCustomPaperSize(rollWithTapeWidth: CGFloat(paper.widthMM),
                                       margins: margins,
                                       unitOfLength: .mm)
        case .dieCut:
            return BRLMCustomPaperSize(dieCutWithTapeWidth: CGFloat(paper.widthMM),
                                       tapeLength: CGFloat(paper.lengthMM),
                                       margins: margins,
                                       gapLength: CGFloat(paper.gapMM),
                                       unitOfLength: .mm)
        case .markRoll:
            return BRLMCustomPaperSize(markRollWithTapeWidth: CGFloat(paper.widthMM),
                                       tapeLength: CGFloat(paper.lengthMM),
                                       margins: margins,
                                       markPosition: CGFloat(paper.markOffsetMM),
                                       markHeight: CGFloat(paper.markLengthMM),
                                       unitOfLength: .mm)
        }
    }

    private static func paperSizeStandard(_ sheet: BrotherSheet) -> BRLMPJPrintSettingsPaperSizeStandard {
        switch sheet {
        case .a4: return .A4
        case .letter: return .letter
        case .legal: return .legal
        case .a5: return .A5
        }
    }

    // MARK: Modeles

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func sdkModel(_ model: BrotherModel) -> BRLMPrinterModel {
        switch model {
        case .PJ_673: return .PJ_673
        case .PJ_763MFi: return .pj_763MFi
        case .PJ_773: return .PJ_773
        case .PJ_822: return .PJ_822
        case .PJ_823: return .PJ_823
        case .PJ_862: return .PJ_862
        case .PJ_863: return .PJ_863
        case .PJ_883: return .PJ_883
        case .MW_145MFi: return .mw_145MFi
        case .MW_260MFi: return .mw_260MFi
        case .MW_170: return .MW_170
        case .MW_270: return .MW_270
        case .RJ_2031: return .RJ_2031
        case .RJ_2050: return .RJ_2050
        case .RJ_2131: return .RJ_2131
        case .RJ_2140: return .RJ_2140
        case .RJ_2150: return .RJ_2150
        case .RJ_3050: return .RJ_3050
        case .RJ_3050Ai: return .rj_3050Ai
        case .RJ_3150: return .RJ_3150
        case .RJ_3150Ai: return .rj_3150Ai
        case .RJ_3230B: return .RJ_3230B
        case .RJ_3235B: return .RJ_3235B
        case .RJ_3250WB: return .RJ_3250WB
        case .RJ_3255WB: return .RJ_3255WB
        case .RJ_4030Ai: return .rj_4030Ai
        case .RJ_4040: return .RJ_4040
        case .RJ_4230B: return .RJ_4230B
        case .RJ_4235B: return .RJ_4235B
        case .RJ_4250WB: return .RJ_4250WB
        case .RJ_4255WB: return .RJ_4255WB
        case .TD_2030A: return .TD_2030A
        case .TD_2120N: return .TD_2120N
        case .TD_2125N: return .TD_2125N
        case .TD_2125NWB: return .TD_2125NWB
        case .TD_2130N: return .TD_2130N
        case .TD_2135N: return .TD_2135N
        case .TD_2135NWB: return .TD_2135NWB
        case .TD_2310D_203: return .TD_2310D_203
        case .TD_2310D_300: return .TD_2310D_300
        case .TD_2320D_203: return .TD_2320D_203
        case .TD_2320D_300: return .TD_2320D_300
        case .TD_2320DF_203: return .TD_2320DF_203
        case .TD_2320DF_300: return .TD_2320DF_300
        case .TD_2320DSA_203: return .TD_2320DSA_203
        case .TD_2320DSA_300: return .TD_2320DSA_300
        case .TD_2350D_203: return .TD_2350D_203
        case .TD_2350D_300: return .TD_2350D_300
        case .TD_2350DF_203: return .TD_2350DF_203
        case .TD_2350DF_300: return .TD_2350DF_300
        case .TD_2350DSA_203: return .TD_2350DSA_203
        case .TD_2350DSA_300: return .TD_2350DSA_300
        case .TD_2350DFSA_203: return .TD_2350DFSA_203
        case .TD_2350DFSA_300: return .TD_2350DFSA_300
        case .TD_4100N: return .TD_4100N
        case .TD_4415D: return .TD_4415D
        case .TD_4420DN: return .TD_4420DN
        case .TD_4425DN: return .TD_4425DN
        case .TD_4425DNF: return .TD_4425DNF
        case .TD_4455DNWB: return .TD_4455DNWB
        case .TD_4520DN: return .TD_4520DN
        case .TD_4525DN: return .TD_4525DN
        case .TD_4550DNWB: return .TD_4550DNWB
        case .TD_4555DNWB: return .TD_4555DNWB
        case .TD_4555DNWBF: return .TD_4555DNWBF
        case .QL_710W: return .QL_710W
        case .QL_720NW: return .QL_720NW
        case .QL_810W: return .QL_810W
        case .QL_820NWB: return .QL_820NWB
        case .QL_1110NWB: return .QL_1110NWB
        case .QL_1115NWB: return .QL_1115NWB
        case .PT_D410: return .PT_D410
        case .PT_D460BT: return .PT_D460BT
        case .PT_D610BT: return .PT_D610BT
        case .PT_D800W: return .PT_D800W
        case .PT_E310BT: return .PT_E310BT
        case .PT_E510: return .PT_E510
        case .PT_E550W: return .PT_E550W
        case .PT_E560BT: return .PT_E560BT
        case .PT_E720BT: return .PT_E720BT
        case .PT_E800W: return .PT_E800W
        case .PT_E850TKW: return .PT_E850TKW
        case .PT_E920BT: return .PT_E920BT
        case .PT_N25BT: return .PT_N25BT
        case .PT_P300BT: return .PT_P300BT
        case .PT_P300BTz: return .pt_P300BTz
        case .PT_P710BT: return .PT_P710BT
        case .PT_P715eBT: return .pt_P715eBT
        case .PT_P750W: return .PT_P750W
        case .PT_P750Wc: return .pt_P750Wc
        case .PT_P900W: return .PT_P900W
        case .PT_P910BT: return .PT_P910BT
        case .PT_P950NW: return .PT_P950NW
        }
    }

    // MARK: Messages d'erreur

    static func searchMessage(_ code: BRLMPrinterSearchErrorCode) -> String? {
        switch code {
        case .noError, .canceled: return nil
        case .alreadySearching: return NSLocalizedString("brother.search.busy", comment: "")
        case .unsupported: return NSLocalizedString("brother.search.unsupported", comment: "")
        case .communicationError: return NSLocalizedString("brother.search.communication", comment: "")
        default: return NSLocalizedString("brother.search.failed", comment: "")
        }
    }

    static func openChannelMessage(_ code: BRLMOpenChannelErrorCode) -> String {
        switch code {
        case .timeout: return NSLocalizedString("brother.open.timeout", comment: "")
        case .openStreamFailure: return NSLocalizedString("brother.open.failed", comment: "")
        default: return NSLocalizedString("brother.open.failed", comment: "")
        }
    }

    static func statusMessage(_ code: BRLMPrinterStatusErrorCode) -> String {
        switch code {
        case .noError: return NSLocalizedString("brother.status.ok", comment: "")
        case .noPaper: return NSLocalizedString("brother.error.noPaper", comment: "")
        case .coverOpen: return NSLocalizedString("brother.error.coverOpen", comment: "")
        case .busy: return NSLocalizedString("brother.error.busy", comment: "")
        case .paperJam: return NSLocalizedString("brother.error.paperJam", comment: "")
        case .batteryEmpty, .batteryTrouble: return NSLocalizedString("brother.error.battery", comment: "")
        case .incompatibleOptionalEquipment: return NSLocalizedString("brother.error.optionalEquipment", comment: "")
        default: return NSLocalizedString("brother.error.printer", comment: "")
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func printMessage(_ code: BRLMPrintErrorCode) -> String {
        let key: String
        switch code {
        case .printerStatusErrorPaperEmpty: key = "brother.error.noPaper"
        case .printerStatusErrorCoverOpen: key = "brother.error.coverOpen"
        case .printerStatusErrorBusy: key = "brother.error.busy"
        case .printerStatusErrorPaperJam, .printerStatusErrorMediaCannotBeFed: key = "brother.error.paperJam"
        case .printerStatusErrorBatteryWeak: key = "brother.error.battery"
        case .printerStatusErrorPrinterTurnedOff: key = "brother.error.turnedOff"
        case .printerStatusErrorOverHeat: key = "brother.error.overheat"
        case .printerStatusErrorCommunicationError, .channelTimeout,
             .channelErrorStreamStatusError: key = "brother.error.communication"
        case .printerStatusErrorIncompatibleOptionalEquipment: key = "brother.error.optionalEquipment"
        case .customPaperSizeError, .setLabelSizeError, .setMarginError,
             .setLengthError: key = "brother.error.paper"
        case .printSettingsError, .printSettingsNotSupportError: key = "brother.error.settings"
        case .printerModelError, .setModelError: key = "brother.error.model"
        case .canceled: key = "brother.error.canceled"
        default: key = "brother.error.printer"
        }
        return NSLocalizedString(key, comment: "") + " (\(code.rawValue))"
    }
}
#endif
