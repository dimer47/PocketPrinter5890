import PocketPrinter5890Kit
import XCTest

final class ResponseDecoderLegacyTests: XCTestCase {
    func testDecodesAsciiModelAndFirmware() {
        XCTAssertEqual(ResponseDecoder.decode(Array("DP-L13".utf8), context: "Lire modele"), "Modele: DP-L13")
        XCTAssertEqual(ResponseDecoder.decode(Array("V3.05".utf8), context: "Lire firmware"), "Firmware: V3.05")
    }

    func testDecodesBatteryFromLeastSignificantByte() {
        XCTAssertEqual(ResponseDecoder.decode([0x00, 0x5c], context: "Lire batterie"), "Batterie: 92%")
    }

    func testDecodesObservedFF03BatteryFrame() {
        XCTAssertEqual(ResponseDecoder.decode([0x02, 0x64, 0x00], context: nil), "Batterie probable: 100%")
        XCTAssertEqual(ResponseDecoder.decode([0x02, 0x64, 0x08], context: nil), "Batterie probable: 100% (flags 0x08)")
        XCTAssertTrue(ResponseDecoder.looksLikeSolicitedResponse([0x02, 0x64, 0x00], context: "Lire batterie"))
    }

    func testDecodesPaperStatus() {
        XCTAssertEqual(ResponseDecoder.decode([0x00], context: "Lire papier"), "Papier: present")
        // Le statut 0x04 est informatif: l'application officielle imprime
        // correctement alors que ce statut est remonte. Il ne doit jamais etre
        // presente comme un blocage.
        XCTAssertTrue(
            ResponseDecoder.decode([0x04], context: "Lire papier").contains("informatif")
        )
    }

    func testDecodesObservedFF03PaperFrame() {
        XCTAssertTrue(ResponseDecoder.decode([0x01, 0x04], context: nil).contains("Credit"))
        XCTAssertTrue(ResponseDecoder.decode([0x01, 0x84], context: nil).contains("Credit"))
        // Un credit ne repond a aucune commande: le prendre pour une reponse
        // consommait le contexte et faisait lire `01 01` comme 1 % de batterie.
        XCTAssertFalse(ResponseDecoder.looksLikeSolicitedResponse([0x01, 0x04], context: "Lire papier"))
    }
}
