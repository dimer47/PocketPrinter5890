import L13Core
import XCTest

final class L13CommandTests: XCTestCase {
    func testDensityCommands() {
        XCTAssertEqual(L13Command.setDensity(.light), [0x10, 0xff, 0x10, 0x00, 0x00])
        XCTAssertEqual(L13Command.setDensity(.medium), [0x10, 0xff, 0x10, 0x00, 0x01])
        XCTAssertEqual(L13Command.setDensity(.strong), [0x10, 0xff, 0x10, 0x00, 0x02])
    }

    func testPrintSequenceStartsWithInitialiseAndDensity() throws {
        let bitmap = try MonochromeBitmap(width: 384, height: 48, bytes: Array(repeating: 0, count: 48 * 48))
        let segments = PrintJobBuilder.segments(
            bitmap: bitmap,
            options: PrintOptions(density: .strong, checkPaper: true)
        )

        // Papier continu: pas de `1F 80` ni de calage `1D 0C`, comme
        // `printOnce()` dans le SDK officiel.
        XCTAssertEqual(segments[0].bytes, L13Command.paperStatus)
        XCTAssertEqual(segments[1].bytes, L13Command.Luck.enablePrinter())
        XCTAssertEqual(segments[2].bytes, L13Command.Luck.wakeup)
        XCTAssertEqual(segments[3].bytes, ESCPOS.initialize)
        // `ESC t` n'est plus emis: ce firmware l'ignore et laisse meme un
        // octet parasite s'imprimer.
        XCTAssertFalse(segments.contains { $0.bytes == ESCPOS.codePageLatin1 })
        XCTAssertEqual(segments[4].bytes, L13Command.setDensity(.strong))
        XCTAssertEqual(Array(segments[5].bytes.prefix(6)), [0x1d, 0x76, 0x30, 0x00, 0x30, 0x00])

        XCTAssertFalse(segments.contains { $0.bytes == L13Command.Luck.position })
        XCTAssertEqual(segments[segments.count - 1].bytes, L13Command.Luck.stopPrintJob)
    }

    func testLabelModeAddsPaperTypeAndPositioning() throws {
        let bitmap = try MonochromeBitmap(width: 384, height: 48, bytes: Array(repeating: 0, count: 48 * 48))
        let segments = PrintJobBuilder.segments(
            bitmap: bitmap,
            options: PrintOptions(paperMode: .label, labelLength: 40)
        )

        XCTAssertTrue(segments.contains { $0.bytes == L13Command.Luck.setPaperType(length: 40) })
        XCTAssertTrue(segments.contains { $0.bytes == L13Command.Luck.position })
    }

    func testRasterHeaderUses48BytesPerLine() throws {
        let bitmap = try MonochromeBitmap(width: 384, height: 240, bytes: Array(repeating: 0, count: 48 * 240))
        XCTAssertEqual(
            Array(RasterEncoder.rasterCommand(for: bitmap).prefix(8)),
            [0x1d, 0x76, 0x30, 0x00, 0x30, 0x00, 0xf0, 0x00]
        )
    }

    func testRasterIsSplitIntoBands() throws {
        let bitmap = try MonochromeBitmap(width: 384, height: 100, bytes: Array(repeating: 0, count: 48 * 100))
        let commands = RasterEncoder.bandedRasterCommands(for: bitmap, bandHeight: 24)

        // 100 lignes en bandes de 24 -> 4 bandes de 24 + 1 bande de 4.
        XCTAssertEqual(commands.count, 5)
        for command in commands {
            XCTAssertEqual(Array(command.prefix(4)), [0x1d, 0x76, 0x30, 0x00])
        }
        // Chaque bande porte sa propre hauteur.
        XCTAssertEqual(commands[0][6], 24)
        XCTAssertEqual(commands[4][6], 4)

        // Aucune donnee perdue: total = en-tetes + pixels.
        let payload = commands.reduce(0) { $0 + $1.count - 8 }
        XCTAssertEqual(payload, 48 * 100)
    }

    func testExperimentalUnknownsAreExplicitOptions() throws {
        let bitmap = try MonochromeBitmap(width: 384, height: 1, bytes: Array(repeating: 0, count: 48))
        let options = PrintOptions(
            includeExperimentalPrePrint: true,
            experimentalPrePrintUsesF130: true,
            includeExperimentalPostPrint: true
        )
        let segments = PrintJobBuilder.segments(bitmap: bitmap, options: options)

        XCTAssertTrue(segments.contains { $0.bytes == L13Command.experimentalPrePrintF130 })
        XCTAssertTrue(segments.contains { $0.bytes == L13Command.experimentalPostPrint })
    }

    func testExperimentalCommandsAreAbsentByDefault() throws {
        let bitmap = try MonochromeBitmap(width: 384, height: 1, bytes: Array(repeating: 0, count: 48))
        let segments = PrintJobBuilder.segments(bitmap: bitmap, options: PrintOptions())

        // `experimentalPrePrintF103` porte 12 octets de bourrage en plus du
        // prefixe; la vraie sequence envoie le reveil separement.
        XCTAssertFalse(segments.contains { $0.bytes == L13Command.experimentalPrePrintF103 })
        XCTAssertFalse(segments.contains { $0.name.contains("experimentale") })
    }
}

final class LuckSequenceTests: XCTestCase {
    func testOfficialCommandBytes() {
        // Octets extraits de l'APK officielle com.printer.lidloffice
        // (LuckPrinter SDK, BaseNormalDevice / DP_D1).
        XCTAssertEqual(L13Command.Luck.enablePrinter(), [0x10, 0xff, 0xf1, 0x03])
        XCTAssertEqual(L13Command.Luck.wakeup, Array(repeating: 0x00, count: 12))
        XCTAssertEqual(L13Command.Luck.setPaperType(), [0x1f, 0x80, 0x01, 0x20])
        XCTAssertEqual(L13Command.Luck.position, [0x1d, 0x0c])
        XCTAssertEqual(L13Command.Luck.stopPrintJob, [0x10, 0xff, 0xf1, 0x45])
    }

    func testSequenceCanBeDisabled() throws {
        let bitmap = try MonochromeBitmap(width: 384, height: 1, bytes: Array(repeating: 0, count: 48))
        let segments = PrintJobBuilder.segments(
            bitmap: bitmap,
            options: PrintOptions(useLuckSequence: false)
        )
        XCTAssertFalse(segments.contains { $0.bytes == L13Command.Luck.stopPrintJob })
    }
}

final class ESCPOSTests: XCTestCase {
    func testAlignment() {
        XCTAssertEqual(ESCPOS.align(.left), [0x1b, 0x61, 0x00])
        XCTAssertEqual(ESCPOS.align(.center), [0x1b, 0x61, 0x01])
        XCTAssertEqual(ESCPOS.align(.right), [0x1b, 0x61, 0x02])
    }

    func testBoldAndUnderline() {
        XCTAssertEqual(ESCPOS.bold(true), [0x1b, 0x45, 0x01])
        XCTAssertEqual(ESCPOS.bold(false), [0x1b, 0x45, 0x00])
        XCTAssertEqual(ESCPOS.underline(2), [0x1b, 0x2d, 0x02])
    }

    func testTextSizeIsClampedAndPacked() {
        XCTAssertEqual(ESCPOS.textSize(width: 1, height: 1), [0x1d, 0x21, 0x00])
        XCTAssertEqual(ESCPOS.textSize(width: 2, height: 2), [0x1d, 0x21, 0x11])
        XCTAssertEqual(ESCPOS.textSize(width: 99, height: 99), [0x1d, 0x21, 0x77])
    }

    func testFrenchAccentsEncodeToCP1252() {
        // "é" vaut 0xE9 en Windows-1252.
        XCTAssertEqual(ESCPOS.encode("é"), [0xe9])
        XCTAssertEqual(ESCPOS.encode("Café").last, 0xe9)
    }

    func testLineAppendsLineFeed() {
        XCTAssertEqual(ESCPOS.line("AB"), [0x41, 0x42, 0x0a])
    }

    func testQRCodeContainsStoreAndPrintFunctions() {
        let bytes = ESCPOS.qrCode("TEST")
        // Fonction 180 (stockage) puis fonction 181 (impression).
        XCTAssertTrue(bytes.contains(0x50))
        XCTAssertEqual(Array(bytes.suffix(8)), [0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x51, 0x30])
    }
}

final class PrintDocumentTests: XCTestCase {
    func testTextElementResetsFormatting() {
        let document = PrintDocument(elements: [.title("HELLO")])
        let bytes = PrintJobBuilder.bytes(document: document, options: PrintOptions())

        // Le gras est active puis desactive, la taille remise a 1.
        XCTAssertTrue(containsSubsequence(bytes, ESCPOS.bold(true)))
        XCTAssertTrue(containsSubsequence(bytes, ESCPOS.bold(false)))
        XCTAssertTrue(containsSubsequence(bytes, ESCPOS.textSize(width: 1, height: 1)))
    }

    func testSeparatorUsesColumnCount() {
        let options = PrintOptions(width: .mm58)
        let document = PrintDocument(elements: [.separator(character: "-")])
        let bytes = PrintJobBuilder.bytes(document: document, options: options)

        let dashes = bytes.filter { $0 == 0x2d }.count
        XCTAssertEqual(dashes, options.textColumns)
        XCTAssertEqual(options.textColumns, 32)
    }

    func testDocumentImageIsBanded() throws {
        let bitmap = try MonochromeBitmap(width: 384, height: 60, bytes: Array(repeating: 0, count: 48 * 60))
        let document = PrintDocument(elements: [.image(bitmap)])
        let bytes = PrintJobBuilder.bytes(document: document, options: PrintOptions(bandHeight: 24))

        // Trois en-tetes raster pour 60 lignes en bandes de 24.
        var headers = 0
        for index in 0..<(bytes.count - 3) where Array(bytes[index..<(index + 4)]) == [0x1d, 0x76, 0x30, 0x00] {
            headers += 1
        }
        XCTAssertEqual(headers, 3)
    }

    private func containsSubsequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for index in 0...(haystack.count - needle.count)
        where Array(haystack[index..<(index + needle.count)]) == needle {
            return true
        }
        return false
    }
}

final class ResponseDecoderTests: XCTestCase {
    func testDecodesOKAcknowledgement() {
        XCTAssertEqual(L13ResponseDecoder.decode([0x4f, 0x4b], context: nil), "OK: commande acceptee")
    }

    func testCreditFrameIsDecodedAsFlowControl() {
        // `01 nn` = credit de flux, confirme par le SDK officiel
        // (d/e.java: credit.addAndGet(bArr[1] & 0xFF)).
        XCTAssertEqual(L13ResponseDecoder.decode([0x01, 0x01], context: nil), "Credit de flux: +1 paquet(s)")
        XCTAssertEqual(L13ResponseDecoder.decode([0x01, 0x04], context: nil), "Credit de flux: +4 paquet(s)")
    }

    func testBatteryDecoding() {
        XCTAssertEqual(L13ResponseDecoder.decode([0x02, 0x64, 0x00], context: nil), "Batterie probable: 100%")
    }
}
