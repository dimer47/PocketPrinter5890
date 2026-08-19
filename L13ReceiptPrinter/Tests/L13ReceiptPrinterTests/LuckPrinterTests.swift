import L13Core
import XCTest

/// Verifie que le portage Swift reproduit fidelement les octets du SDK Java.
final class LuckPrinterPortTests: XCTestCase {
    func testPrintCycleCommands() {
        XCTAssertEqual(LuckPrinter.enablePrinter(), [0x10, 0xff, 0xf1, 0x03])
        XCTAssertEqual(LuckPrinter.wakeup, Array(repeating: 0x00, count: 12))
        XCTAssertEqual(LuckPrinter.stopPrintJob, [0x10, 0xff, 0xf1, 0x45])
        XCTAssertEqual(LuckPrinter.position, [0x1d, 0x0c])
        XCTAssertEqual(LuckPrinter.feedDots(80), [0x1b, 0x4a, 0x50])
    }

    func testSettingsCommands() {
        XCTAssertEqual(LuckPrinter.setDensity(2), [0x10, 0xff, 0x10, 0x00, 0x02])
        XCTAssertEqual(LuckPrinter.setSpeed(5), [0x10, 0xff, 0xc0, 0x05])
        XCTAssertEqual(LuckPrinter.setHeatingLevel(3), [0x1f, 0x70, 0x01, 0x03])
        XCTAssertEqual(LuckPrinter.setPrinterMode(1), [0x10, 0xff, 0x30, 0x27, 0x01])
        XCTAssertEqual(LuckPrinter.factoryReset, [0x10, 0xff, 0x04])
    }

    /// `setShutTimeLuck` encode la valeur sur deux octets gros-boutistes.
    func testAutoShutdownUsesTwoBytes() {
        XCTAssertEqual(LuckPrinter.setAutoShutdown(minutes: 30), [0x10, 0xff, 0x12, 0x00, 0x1e])
        XCTAssertEqual(LuckPrinter.setAutoShutdown(minutes: 300), [0x10, 0xff, 0x12, 0x01, 0x2c])
    }

    /// `printerSetWidth` encode la largeur en petit-boutiste.
    func testSetWidthIsLittleEndian() {
        XCTAssertEqual(LuckPrinter.setWidth(pixels: 384), [0x10, 0xff, 0x15, 0x80, 0x01])
    }

    func testMarkCommands() {
        XCTAssertEqual(LuckPrinter.markPrintFirst, [0x1b, 0xbb, 0xcc])
        XCTAssertEqual(LuckPrinter.markPrintLast, [0x1b, 0xbb, 0xbb])
        XCTAssertEqual(LuckPrinter.markPrintNotLast, [0x1b, 0xbb, 0xaa])
    }

    func testInfoCommands() {
        XCTAssertEqual(LuckPrinter.model, [0x10, 0xff, 0x20, 0xf0])
        XCTAssertEqual(LuckPrinter.firmware, [0x10, 0xff, 0x20, 0xf1])
        XCTAssertEqual(LuckPrinter.serialNumber, [0x10, 0xff, 0x20, 0xf2])
        XCTAssertEqual(LuckPrinter.bootloader, [0x10, 0xff, 0x20, 0xef])
        XCTAssertEqual(LuckPrinter.battery, [0x10, 0xff, 0x50, 0xf1])
        XCTAssertEqual(LuckPrinter.status, [0x10, 0xff, 0x40])
    }

    func testTimeFormatEncoding() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = 19
        parts.hour = 14
        parts.minute = 30
        parts.second = 5
        let date = calendar.date(from: parts)!

        XCTAssertEqual(
            LuckPrinter.setTimeFormat(date, calendar: calendar),
            [0x07, 0xea, 0x08, 0x13, 0x0e, 0x1e, 0x05]
        )
    }
}

final class PrinterStatusTests: XCTestCase {
    func testStatusBitfield() {
        XCTAssertTrue(PrinterStatus(raw: 0x01).isPrinting)
        XCTAssertTrue(PrinterStatus(raw: 0x02).isCoverOpen)
        XCTAssertTrue(PrinterStatus(raw: 0x04).isPaperEmpty)
        XCTAssertTrue(PrinterStatus(raw: 0x08).isBatteryLow)
        XCTAssertTrue(PrinterStatus(raw: 0x20).isCharging)
    }

    func testReadyStatusIsNotBlocking() {
        let status = PrinterStatus(raw: 0x00)
        XCTAssertFalse(status.isBlocking)
        XCTAssertEqual(status.description, "pret")
    }

    func testCoverOpenBlocks() {
        XCTAssertTrue(PrinterStatus(raw: 0x02).isBlocking)
    }
}

@MainActor
final class PocketPrinterFacadeTests: XCTestCase {
    /// Transport de test qui enregistre ce qui lui est envoye.
    final class RecordingTransport: PrinterTransport {
        var sent: [(bytes: [UInt8], label: String)] = []
        func send(_ bytes: [UInt8], label: String) {
            sent.append((bytes, label))
        }
    }

    func testPrintEmitsFullSequence() {
        let transport = RecordingTransport()
        let printer = PocketPrinter(transport: transport)
        printer.print(text: "BONJOUR")

        let all = transport.sent.map(\.bytes)
        XCTAssertEqual(all.first, LuckPrinter.enablePrinter())
        XCTAssertTrue(all.contains(LuckPrinter.wakeup))
        XCTAssertEqual(all.last, LuckPrinter.stopPrintJob)
    }

    func testSettingsAreForwarded() {
        let transport = RecordingTransport()
        let printer = PocketPrinter(transport: transport)
        printer.setDensity(.strong)
        printer.setAutoShutdown(minutes: 15)

        XCTAssertEqual(transport.sent[0].bytes, LuckPrinter.setDensity(2))
        XCTAssertEqual(transport.sent[1].bytes, [0x10, 0xff, 0x12, 0x00, 0x0f])
    }

    func testMultilineTextProducesOneElementPerLine() {
        let transport = RecordingTransport()
        let printer = PocketPrinter(transport: transport)
        printer.print(text: "LIGNE1\nLIGNE2")

        let labels = transport.sent.map(\.label)
        XCTAssertTrue(labels.contains("Texte 1"))
        XCTAssertTrue(labels.contains("Texte 2"))
    }
}

final class FeedAndDemoTests: XCTestCase {
    /// `ESC J` ne prend qu'un octet: au-dela de 255 points la commande
    /// doit etre repetee, pas tronquee.
    func testLongFeedIsSplitAcrossCommands() {
        XCTAssertEqual(ESCPOS.feed(dots: 80), [0x1b, 0x4a, 0x50])
        XCTAssertEqual(ESCPOS.feed(dots: 255), [0x1b, 0x4a, 0xff])
        XCTAssertEqual(ESCPOS.feed(dots: 400), [0x1b, 0x4a, 0xff, 0x1b, 0x4a, 0x91])
        XCTAssertEqual(ESCPOS.feed(dots: 0), [])

        // Le total avance doit correspondre exactement a la demande.
        let bytes = ESCPOS.feed(dots: 1000)
        let total = stride(from: 2, to: bytes.count, by: 3).reduce(0) { $0 + Int(bytes[$1]) }
        XCTAssertEqual(total, 1000)
    }

    func testTrailingFeedAboveByteLimit() throws {
        let bitmap = try MonochromeBitmap(width: 384, height: 1, bytes: Array(repeating: 0, count: 48))
        let segments = PrintJobBuilder.segments(
            bitmap: bitmap,
            options: PrintOptions(trailingFeedDots: 600)
        )
        let feed = try XCTUnwrap(segments.first { $0.name.contains("Degagement") })
        let total = stride(from: 2, to: feed.bytes.count, by: 3).reduce(0) { $0 + Int(feed.bytes[$1]) }
        XCTAssertEqual(total, 600)
    }

    /// Un document vide sert de degagement manuel: il doit tout de meme
    /// porter la sequence d'activation, sinon le firmware l'ignore.
    func testEmptyDocumentStillCarriesActivation() {
        let bytes = PrintJobBuilder.bytes(
            document: PrintDocument(),
            options: PrintOptions(trailingFeedDots: 100)
        )
        XCTAssertEqual(Array(bytes.prefix(4)), LuckPrinter.enablePrinter())
        XCTAssertEqual(Array(bytes.suffix(4)), LuckPrinter.stopPrintJob)
    }

    /// Le texte de la demo reste natif; seuls les codes sont rasterises,
    /// le firmware A2Y n'implementant pas `GS ( k` ni `GS k`.
    func testDemoUsesNativeTextAndRasterisedCodes() {
        let bytes = PrintJobBuilder.bytes(
            document: DemoDocuments.weatherAndHoroscope(),
            options: PrintOptions()
        )

        // Les codes passent bien par le raster.
        var rasterCommands = 0
        for index in 0..<max(0, bytes.count - 3)
        where Array(bytes[index..<(index + 4)]) == [0x1d, 0x76, 0x30, 0x00] {
            rasterCommands += 1
        }
        XCTAssertGreaterThan(rasterCommands, 0)

        // Aucune commande QR native: elle s'imprimerait en clair.
        var hasNativeQR = false
        for index in 0..<max(0, bytes.count - 2)
        where Array(bytes[index..<(index + 3)]) == [0x1d, 0x28, 0x6b] {
            hasNativeQR = true
        }
        XCTAssertFalse(hasNativeQR, "GS ( k s'imprime en texte sur ce firmware")

        // Et le texte, lui, reste natif: on doit retrouver la chaine en clair.
        let meteo = Array("METEO".utf8)
        var hasPlainText = false
        for index in 0..<max(0, bytes.count - meteo.count)
        where Array(bytes[index..<(index + meteo.count)]) == meteo {
            hasPlainText = true
        }
        XCTAssertTrue(hasPlainText)
    }

    func testColumnsPadToWidth() {
        XCTAssertEqual(DemoDocuments.columns("A", "B", width: 10).count, 10)
        XCTAssertEqual(DemoDocuments.columns("Vent", "23 km/h", width: 32).count, 32)
        // Jamais de chevauchement, meme si le contenu est trop long.
        XCTAssertFalse(DemoDocuments.columns(String(repeating: "X", count: 30), "YYYYY", width: 32).isEmpty)
    }
}

final class BatteryDecodingTests: XCTestCase {
    /// Le SDK lit le pourcentage dans le deuxieme octet de la reponse a
    /// `10 FF 50 F1` (`lambda$getBatteryLuck$6`: `bArr[1]`).
    func testBatteryCommandMatchesSDK() {
        XCTAssertEqual(LuckPrinter.battery, [0x10, 0xff, 0x50, 0xf1])
    }

    func testBatteryFrameDecoding() {
        // Trames reellement observees sur cette machine.
        XCTAssertEqual(L13ResponseDecoder.decode([0x02, 0x64, 0x00], context: nil), "Batterie probable: 100%")
        XCTAssertTrue(L13ResponseDecoder.decode([0x02, 0x62, 0x00], context: nil).contains("98"))
    }

    /// Trame reellement observee en reponse a `10 FF 50 F1`: `00 62`.
    /// Le premier octet vaut 0x00, pas 0x02 comme l'emission spontanee.
    func testBatteryReplyFormFromRealLog() {
        XCTAssertTrue(
            L13ResponseDecoder.looksLikeSolicitedResponse([0x00, 0x62], context: "Lire batterie")
        )
        XCTAssertEqual(
            L13ResponseDecoder.decode([0x00, 0x62], context: "Lire batterie"),
            "Batterie: 98%"
        )
        // L'autre forme, emise spontanement, doit rester reconnue.
        XCTAssertTrue(
            L13ResponseDecoder.looksLikeSolicitedResponse([0x02, 0x64, 0x00], context: "Lire batterie")
        )
    }

    /// Une trame batterie fait 3 octets et commence par 0x02: elle ne doit
    /// pas etre confondue avec un credit de flux `01 nn`.
    func testBatteryIsNotConfusedWithCredit() {
        let credit = L13ResponseDecoder.decode([0x01, 0x64], context: nil)
        let battery = L13ResponseDecoder.decode([0x02, 0x64, 0x00], context: nil)
        XCTAssertTrue(credit.contains("Credit"))
        XCTAssertTrue(battery.contains("Batterie"))
    }
}

final class CodeGenerationTests: XCTestCase {
    func testQRCodeOccupiesPrintWidth() throws {
        let qr = try CodeBitmaps.qrCode("https://exemple.fr")
        // Le bitmap fait toute la largeur pour que le code soit centre.
        XCTAssertEqual(qr.width, 384)
        XCTAssertGreaterThan(qr.height, 0)
        XCTAssertLessThanOrEqual(qr.height, 384)
    }

    func testQRCodeHasPlausibleDensity() throws {
        let qr = try CodeBitmaps.qrCode("https://exemple.fr")
        let black = qr.bytes.reduce(0) { $0 + $1.nonzeroBitCount }
        let total = qr.width * qr.height
        XCTAssertGreaterThan(black, total / 20)
        XCTAssertLessThan(black, total / 2)
    }

    func testEmptyContentIsRejected() {
        XCTAssertThrowsError(try CodeBitmaps.qrCode(""))
        XCTAssertThrowsError(try CodeBitmaps.barcode(""))
    }

    // MARK: - Codes-barres lineaires

    func testCode128AcceptsASCII() throws {
        let barcode = try CodeBitmaps.barcode("ABC-123", symbology: .code128, height: 70)
        XCTAssertEqual(barcode.width, 384)
        XCTAssertEqual(barcode.height, 70)
    }

    func testCode128RejectsNonASCII() {
        XCTAssertThrowsError(try Barcode1D.pattern(for: "Café", symbology: .code128))
    }

    func testCode39RejectsUnsupportedCharacter() {
        XCTAssertThrowsError(try Barcode1D.pattern(for: "abc@", symbology: .code39))
    }

    /// Cle de controle validee sur l'exemple de la norme EAN-13.
    func testEANCheckDigitMatchesStandard() {
        XCTAssertEqual(Barcode1D.checkDigit([5, 9, 0, 1, 2, 3, 4, 1, 2, 3, 4, 5]), 7)
        XCTAssertEqual(Barcode1D.checkDigit([9, 6, 3, 8, 5, 0, 7]), 4)
    }

    /// La cle est ajoutee si elle manque, et verifiee si elle est fournie.
    func testEANAcceptsWithOrWithoutCheckDigit() throws {
        let withKey = try Barcode1D.pattern(for: "5901234123457", symbology: .ean13)
        let withoutKey = try Barcode1D.pattern(for: "590123412345", symbology: .ean13)
        XCTAssertEqual(withKey, withoutKey)
    }

    func testEANRejectsWrongCheckDigit() {
        XCTAssertThrowsError(try Barcode1D.pattern(for: "5901234123450", symbology: .ean13))
    }

    /// EAN-13 fait 95 modules: 3 + 42 + 5 + 42 + 3.
    func testEAN13PatternLength() throws {
        let pattern = try Barcode1D.pattern(for: "5901234123457", symbology: .ean13)
        XCTAssertEqual(pattern.count, 95)
    }

    func testEAN8PatternLength() throws {
        let pattern = try Barcode1D.pattern(for: "96385074", symbology: .ean8)
        XCTAssertEqual(pattern.count, 67)
    }

    /// Les codes doivent rester purement noir et blanc, jamais trames.
    func testBarcodeIsNotDithered() throws {
        let barcode = try CodeBitmaps.barcode("TEST", height: 20)
        // Toutes les lignes sont identiques: un code-barres est invariant
        // verticalement.
        let stride = barcode.widthBytes
        let firstRow = Array(barcode.bytes[0..<stride])
        let lastRow = Array(barcode.bytes[(stride * 19)..<(stride * 20)])
        XCTAssertEqual(firstRow, lastRow)
    }
}


final class CreditFrameIsolationTests: XCTestCase {
    /// Regression: `01 01` etait pris pour la reponse a « Lire batterie »,
    /// ce qui affichait 1 % au lieu des 98 % que portait la trame suivante.
    func testCreditFrameIsNeverASolicitedResponse() {
        for context in ["Lire batterie", "Lire papier", "Lire modele", "Lire firmware"] {
            XCTAssertFalse(
                L13ResponseDecoder.looksLikeSolicitedResponse([0x01, 0x01], context: context),
                "Un credit ne doit pas consommer le contexte \(context)"
            )
            XCTAssertFalse(
                L13ResponseDecoder.looksLikeSolicitedResponse([0x01, 0x04], context: context)
            )
        }
    }

    /// La vraie reponse batterie, elle, doit bien etre reconnue.
    func testRealBatteryReplyIsStillRecognised() {
        XCTAssertTrue(
            L13ResponseDecoder.looksLikeSolicitedResponse([0x00, 0x62], context: "Lire batterie")
        )
        XCTAssertEqual(
            L13ResponseDecoder.decode([0x00, 0x62], context: "Lire batterie"),
            "Batterie: 98%"
        )
    }

    /// Un credit reste decode comme tel dans la console.
    func testCreditStillDecodedForDisplay() {
        XCTAssertTrue(L13ResponseDecoder.decode([0x01, 0x01], context: nil).contains("Credit"))
    }
}

final class TextLayoutTests: XCTestCase {
    /// Regression: le firmware coupait au caractere pres, produisant
    /// « l'apres-m » puis « idi. » sur le ticket imprime.
    func testLongLineIsWrappedOnSpaces() {
        let lines = TextLayout.wrap("Ciel voile, eclaircies l'apres-midi.", columns: 32)
        XCTAssertEqual(lines, ["Ciel voile, eclaircies", "l'apres-midi."])
        XCTAssertTrue(lines.allSatisfy { $0.count <= 32 })
    }

    func testShortLineIsUntouched() {
        XCTAssertEqual(TextLayout.wrap("METEO", columns: 32), ["METEO"])
    }

    /// Un mot plus long qu'une ligne doit etre coupe, faute de mieux.
    func testOverlongWordIsSplit() {
        let lines = TextLayout.wrap(String(repeating: "A", count: 70), columns: 32)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines.allSatisfy { $0.count <= 32 })
    }

    func testExplicitNewlinesArePreserved() {
        XCTAssertEqual(TextLayout.wrap("A\nB", columns: 32), ["A", "B"])
    }

    /// Une police agrandie reduit d'autant le nombre de colonnes.
    func testColumnsShrinkWithTextSize() {
        XCTAssertEqual(TextLayout.columns(printWidth: 384, size: 1), 32)
        XCTAssertEqual(TextLayout.columns(printWidth: 384, size: 2), 16)
    }

    func testColumnsHelperNeverOverlaps() {
        let line = TextLayout.columns("Une etiquette tres longue", "VALEUR", width: 20)
        XCTAssertLessThanOrEqual(line.count, 20)
    }
}

final class TransliterationTests: XCTestCase {
    /// Le firmware imprime un carre plein pour `°` et les accents.
    func testDegreeAndAccentsBecomeASCII() {
        XCTAssertEqual(ESCPOS.transliterate("18°C"), "18degC")
        XCTAssertEqual(ESCPOS.transliterate("café"), "cafe")
        XCTAssertEqual(ESCPOS.transliterate("août"), "aout")
        XCTAssertEqual(ESCPOS.transliterate("Ça va"), "Ca va")
    }

    func testSymbolsAreReplaced() {
        XCTAssertEqual(ESCPOS.transliterate("12 €"), "12 EUR")
        XCTAssertEqual(ESCPOS.transliterate("½"), "1/2")
        XCTAssertEqual(ESCPOS.transliterate("cœur"), "coeur")
    }

    func testASCIIIsUntouched() {
        XCTAssertEqual(ESCPOS.transliterate("METEO 2026 - 18C"), "METEO 2026 - 18C")
    }

    /// Apres transliteration, plus aucun octet hors ASCII ne part.
    func testResultIsPureASCII() {
        let text = ESCPOS.transliterate("18°C à Lille, café, août, ½ €")
        XCTAssertTrue(text.allSatisfy(\.isASCII))
    }
}
