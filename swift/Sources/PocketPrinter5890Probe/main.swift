import CoreBluetooth
import Foundation
import PocketPrinter5890BLE
import PocketPrinter5890Kit

@main
final class PocketPrinter5890Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var target: CBPeripheral?
    private var profile: BLEUARTProfile?
    private var rx: CBCharacteristic?
    private var tx: CBCharacteristic?
    private var didStartNotifications = false
    private var queue: [[UInt8]] = []
    private var waiting = false
    private let shouldFeed = CommandLine.arguments.contains("--feed")
    private let shouldFeedBig = CommandLine.arguments.contains("--feed-big")
    private let shouldPrintTest = CommandLine.arguments.contains("--print-test")
    private let shouldProbeCodePages = CommandLine.arguments.contains("--code-pages")
    private let selectedProfileName = CommandLine.arguments
        .first { $0.hasPrefix("--profile=") }?
        .replacingOccurrences(of: "--profile=", with: "")
        .lowercased()
    private let timeout: TimeInterval = {
        let args = CommandLine.arguments
        if args.contains("--print-test") { return 45 }
        if args.contains("--code-pages") { return 40 }
        if args.contains("--feed-big") { return 25 }
        if args.contains("--feed") { return 18 }
        return 8
    }()

    static func main() {
        let probe = PocketPrinter5890Probe()
        probe.run()
    }

    private func run() {
        print("PocketPrinter5890Probe: scan BLE, cible Mini Pocket Printer / L13 / services UART connus")
        print("Option: ajouter --feed pour envoyer une avance papier 1B 4A 28 apres connexion")
        print("Option: ajouter --print-test pour envoyer une petite mire raster 96 x 48")
        print("Option: ajouter --profile=transparent|ff00|18f0|e781 pour forcer un UART BLE")
        central = CBCentralManager(delegate: self, queue: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            print("Fin du diagnostic.")
            exit(0)
        }
        RunLoop.main.run()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            print("Bluetooth indisponible: \(central.state.rawValue)")
            return
        }
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "BLE \(peripheral.identifier.uuidString.prefix(8))"
        let advertised = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let likelyName = name.lowercased().contains("printer")
            || name.lowercased().contains("pocket")
            || name.lowercased().contains("l13")
        let likelyService = advertised.contains { PrinterBLEProfiles.allServiceUUIDs.contains($0) }
        guard likelyName || likelyService else { return }

        print("Trouve: \(name)  uuid=\(peripheral.identifier.uuidString)  rssi=\(RSSI)")
        if !advertised.isEmpty {
            print("  services annonces: \(advertised.map(\.uuidString).joined(separator: ", "))")
        }

        guard target == nil else { return }
        target = peripheral
        peripheral.delegate = self
        central.stopScan()
        print("Connexion a \(name)...")
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connecte. Decouverte des services...")
        peripheral.discoverServices(nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            print("Erreur services: \(error.localizedDescription)")
            return
        }
        let services = peripheral.services ?? []
        print("Services trouves:")
        for service in services {
            print("  \(service.uuid.uuidString)")
        }
        let candidates = orderedProfiles()
        guard let selected = candidates.first(where: { wanted in
            services.contains { $0.uuid == wanted.service }
        }) else {
            print("Aucun service UART L13 connu trouve.")
            return
        }
        profile = selected
        print("Profil retenu: \(selected.id) / \(selected.service.uuidString)")
        guard let service = services.first(where: { $0.uuid == selected.service }) else { return }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            print("Erreur caracteristiques: \(error.localizedDescription)")
            return
        }
        guard let profile else { return }
        print("Caracteristiques \(service.uuid.uuidString):")
        for characteristic in service.characteristics ?? [] {
            print("  \(characteristic.uuid.uuidString) props=\(properties(characteristic.properties))")
            if characteristic.uuid == profile.rx {
                rx = characteristic
            }
            if characteristic.uuid == profile.tx {
                tx = characteristic
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            if characteristic.properties.contains(.notify), characteristic.uuid != profile.tx {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        print("RX retenu: \(rx?.uuid.uuidString ?? "-")")
        print("TX retenu: \(tx?.uuid.uuidString ?? "-")")
        if tx == nil {
            beginCommands()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            print("Notification erreur \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            return
        }
        print("Notification active: \(characteristic.uuid.uuidString)")
        guard characteristic.uuid == tx?.uuid, !didStartNotifications else { return }
        didStartNotifications = true
        beginCommands()
    }

    private func beginCommands() {
        enqueue(PrinterCommand.model, "modele")
        enqueue(PrinterCommand.firmware, "firmware")
        enqueue(PrinterCommand.battery, "batterie")
        enqueue(PrinterCommand.paperStatus, "papier")
        if shouldFeedBig {
            // Sequence exacte extraite de l'application officielle
            // (LuckPrinter SDK, classe DP_D1.printTagOnce dont herite
            // MiniPocketPrinter, le modele annonce par cette machine).
            enqueue([0x10, 0xff, 0xf1, 0x03], "enablePrinter 10 FF F1 03")
            enqueue(Array(repeating: 0x00, count: 12), "wakeup 12 zeros")
            enqueue([0x1f, 0x80, 0x01, 0x20], "setPaperType 1F 80 01 20")
            enqueue(ESCPOS.feedLines(6), "avance 6 lignes")
            enqueue(ESCPOS.feedDots(200), "avance 200 points")
            enqueue([0x1d, 0x0c], "printerPosition 1D 0C")
            enqueue([0x10, 0xff, 0xf1, 0x45], "stopPrintJob 10 FF F1 45")
        }
        if shouldFeed {
            enqueue(PrinterCommand.feedDots(0x28), "avance papier")
        }
        if shouldProbeCodePages {
            let segments = PrintJobBuilder.segments(
                document: DemoDocuments.codePageProbe(),
                options: PrintOptions(density: .strong)
            )
            for segment in segments {
                enqueue(segment.bytes, segment.name)
            }
        }
        if shouldPrintTest {
            enqueuePrintTest()
        }
        drain()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            print("RX erreur \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            return
        }
        let bytes = Array(characteristic.value ?? Data())
        print("RX \(characteristic.uuid.uuidString): \(Hex.encode(bytes))  ascii=\(ascii(bytes))")
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        waiting = false
        drain()
    }

    private func enqueue(_ bytes: [UInt8], _ label: String) {
        print("QUEUE \(label): \(Hex.encode(bytes))")
        queue.append(bytes)
    }

    private func drain() {
        guard !waiting, let peripheral = target, let rx else { return }
        guard !queue.isEmpty else { return }
        guard peripheral.canSendWriteWithoutResponse else { return }
        var request = queue.removeFirst()
        let size = min(20, peripheral.maximumWriteValueLength(for: .withoutResponse), request.count)
        let chunk = Array(request.prefix(size))
        request.removeFirst(size)
        if !request.isEmpty {
            queue.insert(request, at: 0)
        }
        print("TX \(rx.uuid.uuidString): \(Hex.encode(chunk))")
        waiting = true
        peripheral.writeValue(Data(chunk), for: rx, type: .withoutResponse)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.waiting = false
            self?.drain()
        }
    }

    private func enqueuePrintTest() {
        // Mire de diagnostic a la largeur native de la machine (384 px).
        enqueuePrintTest(width: .mm58)
    }

    /// Imprime une mire pour une largeur donnee.
    ///
    /// Utile pour confirmer visuellement la bonne largeur: une mire trop etroite
    /// laisse une large marge blanche a droite, une mire trop large est tronquee
    /// ou repliee.
    private func enqueuePrintTest(width: PrinterWidth) {
        do {
            let w = width.pixels
            let height = 64
            var pixels = Array(repeating: false, count: w * height)
            for y in 0..<height {
                for x in 0..<w {
                    let border = x == 0 || x == w - 1 || y == 0 || y == height - 1
                    let ruler = y < 12 && x % 8 == 0
                    let longRuler = y < 20 && x % 64 == 0
                    let checker = (x / 8 + y / 8).isMultiple(of: 2) && y > 24 && y < 48
                    let solid = y >= 52 && y < 60
                    pixels[y * w + x] = border || ruler || longRuler || checker || solid
                }
            }
            let bitmap = try RasterEncoder.encodeBlackPixels(pixels, width: w, height: height)
            // PrintJobBuilder encadre desormais le travail par la sequence
            // d'activation officielle, indispensable sur cette machine.
            let segments = PrintJobBuilder.segments(
                bitmap: bitmap,
                options: PrintOptions(width: width, density: .strong)
            )
            for segment in segments {
                enqueue(segment.bytes, segment.name)
            }
        } catch {
            print("Erreur creation mire: \(error.localizedDescription)")
        }
    }

    private func orderedProfiles() -> [BLEUARTProfile] {
        guard let selectedProfileName else { return PrinterBLEProfiles.preferred }
        let forced: BLEUARTProfile?
        switch selectedProfileName {
        case "transparent", "microchip", "49535343":
            forced = PrinterBLEProfiles.transparentUART
        case "ff00":
            forced = PrinterBLEProfiles.ff00
        case "18f0":
            forced = PrinterBLEProfiles.service18F0
        case "e781":
            forced = PrinterBLEProfiles.combinedE781
        default:
            forced = nil
        }
        guard let forced else { return PrinterBLEProfiles.preferred }
        return [forced] + PrinterBLEProfiles.preferred.filter { $0.id != forced.id }
    }

    private func properties(_ properties: CBCharacteristicProperties) -> String {
        var result: [String] = []
        if properties.contains(.notify) { result.append("notify") }
        if properties.contains(.write) { result.append("write") }
        if properties.contains(.writeWithoutResponse) { result.append("writeWithoutResponse") }
        if properties.contains(.read) { result.append("read") }
        return result.joined(separator: "|")
    }

    private func ascii(_ bytes: [UInt8]) -> String {
        String(bytes: bytes.filter { $0 >= 0x20 && $0 <= 0x7e }, encoding: .ascii) ?? ""
    }
}
