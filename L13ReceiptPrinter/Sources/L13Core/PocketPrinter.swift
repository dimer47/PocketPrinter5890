import Foundation

/// Transport capable d'envoyer des octets a l'imprimante.
///
/// Le protocole isole la librairie du moyen de communication: BLE aujourd'hui,
/// USB ou Bluetooth Classic plus tard, sans rien changer au reste du code.
@MainActor
public protocol PrinterTransport: AnyObject {
    func send(_ bytes: [UInt8], label: String)
}

/// Equivalent Swift de l'objet `Printer` du LuckPrinter SDK.
///
/// Cette facade rassemble le cycle d'impression et les reglages en une API
/// unique, pour eviter d'avoir a assembler les commandes a la main.
///
/// ```swift
/// let printer = PocketPrinter(transport: bleTransport)
/// printer.readDeviceInformation()
/// printer.setDensity(.strong)
///
/// var document = PrintDocument()
/// document.append(.title("BOULANGERIE"))
/// document.append(.qrCode("https://exemple.fr"))
/// printer.print(document)
/// ```
@MainActor
public final class PocketPrinter {
    public weak var transport: PrinterTransport?
    /// Options appliquees par defaut a chaque impression.
    public var options: PrintOptions

    public init(transport: PrinterTransport?, options: PrintOptions = PrintOptions()) {
        self.transport = transport
        self.options = options
    }

    // MARK: - Impression

    /// Imprime un document compose.
    public func print(_ document: PrintDocument, options: PrintOptions? = nil) {
        send(PrintJobBuilder.segments(document: document, options: options ?? self.options))
    }

    /// Imprime un bitmap deja converti.
    public func print(_ bitmap: MonochromeBitmap, options: PrintOptions? = nil) {
        send(PrintJobBuilder.segments(bitmap: bitmap, options: options ?? self.options))
    }

    /// Imprime une ou plusieurs lignes de texte.
    public func print(
        text: String,
        size: Int = 1,
        bold: Bool = false,
        alignment: ESCPOS.Alignment = .left,
        options: PrintOptions? = nil
    ) {
        let elements = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            PrintElement.text(
                String($0),
                size: size,
                bold: bold,
                underline: false,
                inverted: false,
                alignment: alignment
            )
        }
        print(PrintDocument(elements: elements), options: options)
    }

    /// Avance le papier de n points sans rien imprimer.
    public func feed(dots: UInt8) {
        transport?.send(LuckPrinter.feedDots(dots), label: "Avance \(dots) points")
    }

    // MARK: - Reglages

    public func setDensity(_ density: L13Density) {
        options.density = density
        transport?.send(LuckPrinter.setDensity(density.rawValue), label: "Densite \(density.title)")
    }

    /// Vitesse d'impression. Non verifiee sur ce firmware.
    public func setSpeed(_ level: UInt8) {
        transport?.send(LuckPrinter.setSpeed(level), label: "Vitesse \(level)")
    }

    /// Niveau de chauffe de la tete. Non verifiee sur ce firmware.
    public func setHeatingLevel(_ level: UInt8) {
        transport?.send(LuckPrinter.setHeatingLevel(level), label: "Chauffe \(level)")
    }

    /// Delai d'extinction automatique, en minutes.
    public func setAutoShutdown(minutes: Int) {
        transport?.send(
            LuckPrinter.setAutoShutdown(minutes: minutes),
            label: "Extinction auto \(minutes) min"
        )
    }

    /// Regle l'horloge interne. Non verifiee sur ce firmware.
    public func setClock(_ date: Date = Date()) {
        transport?.send(LuckPrinter.setTimeFormat(date), label: "Horloge")
    }

    /// Retour aux reglages d'usine. Non verifiee sur ce firmware.
    public func factoryReset() {
        transport?.send(LuckPrinter.factoryReset, label: "Reglages d'usine")
    }

    // MARK: - Informations

    public func readDeviceInformation() {
        transport?.send(LuckPrinter.model, label: "Lire modele")
        transport?.send(LuckPrinter.firmware, label: "Lire firmware")
        transport?.send(LuckPrinter.battery, label: "Lire batterie")
        transport?.send(LuckPrinter.status, label: "Lire papier")
    }

    public func readSerialNumber() {
        transport?.send(LuckPrinter.serialNumber, label: "Lire numero de serie")
    }

    public func readBootloader() {
        transport?.send(LuckPrinter.bootloader, label: "Lire bootloader")
    }

    public func readSettings() {
        transport?.send(LuckPrinter.getDensity, label: "Lire densite")
        transport?.send(LuckPrinter.getSpeed, label: "Lire vitesse")
        transport?.send(LuckPrinter.getAutoShutdown, label: "Lire extinction auto")
    }

    // MARK: - Commande brute

    /// Echappatoire pour une commande non couverte par la librairie.
    public func sendRaw(_ bytes: [UInt8], label: String = "Commande brute") {
        transport?.send(bytes, label: label)
    }

    private func send(_ segments: [PrintSegment]) {
        for segment in segments {
            transport?.send(segment.bytes, label: segment.name)
        }
    }
}
