import PocketPrinter5890Kit
import XCTest

final class PrinterCatalogTests: XCTestCase {
    func testTD4550DNWBIsTheDefaultAndSupportsBLE() {
        XCTAssertEqual(BrotherModel.defaultModel, .TD_4550DNWB)
        XCTAssertEqual(BrotherModel.TD_4550DNWB.series, .td)
        XCTAssertTrue(BrotherModel.TD_4550DNWB.supportsBLE)
        XCTAssertEqual(BrotherModel.TD_4550DNWB.appConnections, [.ble, .wifi])
    }

    func testOlderTD4ModelsHaveNoBLE() {
        // Le manuel du SDK ne leur connait pas de BLE: ne pas le proposer.
        for model in [BrotherModel.TD_4420DN, .TD_4520DN, .TD_4100N, .TD_4415D] {
            XCTAssertFalse(model.supportsBLE, model.rawValue)
        }
    }

    func testAdvertisedNameMatchesTheLongestModel() {
        XCTAssertEqual(BrotherModel.matching(advertisedName: "Brother TD-4550DNWB"), .TD_4550DNWB)
        XCTAssertEqual(BrotherModel.matching(advertisedName: "Brother TD-4555DNWBF"), .TD_4555DNWBF)
        XCTAssertEqual(BrotherModel.matching(advertisedName: "Brother PT-P750Wc"), .PT_P750Wc)
        XCTAssertEqual(BrotherModel.matching(advertisedName: "Brother TD-2350DFSA"), .TD_2350DFSA_203)
        XCTAssertNil(BrotherModel.matching(advertisedName: "Mini Pocket Printer_BLE"))
    }

    func testEveryModelHasACompatibleDefaultMedia() {
        for model in BrotherModel.allCases {
            XCTAssertTrue(BrotherMedia.defaultMedia(for: model).isCompatible(with: model), model.rawValue)
        }
    }

    func testPaperDependsOnThePrinter() {
        // TD-4: jusqu'a 4 pouces. TD-2: 2 pouces. QL: references DK du SDK.
        XCTAssertTrue(BrotherModel.TD_4550DNWB.paperPresets.contains(.roll(widthMM: 102)))
        XCTAssertFalse(BrotherModel.TD_2135NWB.paperPresets.contains(.roll(widthMM: 102)))
        XCTAssertTrue(BrotherModel.QL_820NWB.paperPresets.isEmpty)
        XCTAssertFalse(BrotherMedia.custom(.roll(widthMM: 102)).isCompatible(with: .TD_2135NWB))
        XCTAssertFalse(BrotherMedia.qlLabel(0).isCompatible(with: .TD_4550DNWB))
    }

    func testSDKLabelOrderMatchesTheHeaders() {
        // L'index sert de valeur brute de l'enumeration du SDK.
        XCTAssertEqual(BrotherLabelSize.ql.count, 33)
        XCTAssertEqual(BrotherLabelSize.ql.first?.name, "DieCutW17H54")
        XCTAssertEqual(BrotherLabelSize.ql.last?.name, "RoundW58DIA")
        XCTAssertEqual(BrotherLabelSize.pt.count, 18)
        XCTAssertEqual(BrotherLabelSize.pt[3].name, "Width12mm")
    }

    func testCutterSupportPerSeries() {
        XCTAssertEqual(BrotherSeries.td.cutter, .optionalUnit)
        XCTAssertTrue(BrotherSeries.td.cutter.supportsCutAtEnd)
        XCTAssertFalse(BrotherSeries.rj.cutter.isControllable)
        XCTAssertFalse(BrotherSeries.pt.cutter.supportsCutAtEnd)
    }

    func testCutOptionsAreOffByDefaultAndClamped() {
        let options = BrotherCutOptions()
        XCTAssertFalse(options.autoCut)
        XCTAssertFalse(options.cutAtEnd)
        XCTAssertEqual(BrotherCutOptions(cutEveryPages: 0).clampedCutEveryPages, 1)
        XCTAssertEqual(BrotherCutOptions(cutEveryPages: 900).clampedCutEveryPages, 255)
    }

    func testMediaRoundTripsThroughCodable() throws {
        let media = BrotherMedia.custom(.dieCut(widthMM: 102, lengthMM: 152))
        let data = try JSONEncoder().encode(media)
        XCTAssertEqual(try JSONDecoder().decode(BrotherMedia.self, from: data), media)
    }

    func testRasterizerScalesWithoutChangingLayout() throws {
        var document = PrintDocument()
        document.append(.title("BROTHER"))
        document.append(.separator())
        document.append(.text("Ligne de test"))
        document.append(try .qr("https://exemple.fr"))

        let base = try DocumentRasterizer().image(document)
        let large = try DocumentRasterizer().image(document, scale: 3)

        XCTAssertEqual(base.width, 384)
        XCTAssertEqual(large.width, 384 * 3)
        XCTAssertEqual(large.height, base.height * 3)
    }

    func testScaledReceiptKeepsProportions() throws {
        let renderer = ReceiptRenderer()
        let image = try renderer.image(.sample, scale: 2)
        let preview = try renderer.previewImage(.sample)
        XCTAssertEqual(image.width, preview.width * 2)
        XCTAssertEqual(image.height, preview.height * 2)
    }
}
