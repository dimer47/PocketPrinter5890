import CoreGraphics
import Foundation
import PocketPrinter5890BLE
import PocketPrinter5890Kit

/// Envoie un travail a l'imprimante choisie.
///
/// La pocket 5890 recoit de l'ESC/POS par le transport BLE de la librairie.
/// Une Brother recoit une image par le Brother Print SDK: le document est
/// alors dessine avec la meme mise en page, a la resolution de sa tete.
@MainActor
struct PrintDispatcher {
    let setup: PrinterSetup
    let transport: PocketPrinter5890BLE
    let brother: BrotherPrinterService
    let options: PrintOptions

    var isBrother: Bool { setup.brand == .brother }

    var isReady: Bool {
        isBrother ? brother.canPrint : transport.isConnected
    }

    /// Largeur de mise en page: celle de la 5890 choisie dans les reglages,
    /// et 384 points pour une Brother, que le SDK met a l'echelle du papier.
    var layoutWidth: Int {
        isBrother ? MonochromeBitmap.nativeWidth : options.width.pixels
    }

    func print(_ document: PrintDocument) {
        guard isBrother else {
            PocketPrinter(transport: transport, options: options).print(document, options: options)
            return
        }
        let width = layoutWidth
        brother.print(job: setup.brotherJob) { scale in
            try DocumentRasterizer(width: width).image(document, scale: scale)
        }
    }

    func print(text: String, size: Int, alignment: ESCPOS.Alignment) {
        guard isBrother else {
            PocketPrinter(transport: transport, options: options)
                .print(text: text, size: size, alignment: alignment, options: options)
            return
        }
        let elements = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            PrintElement.text(String($0), size: size, bold: false, underline: false,
                              inverted: false, alignment: alignment)
        }
        print(PrintDocument(elements: elements))
    }

    func print(_ receipt: Receipt, mode: ReceiptPrintMode) {
        switch (isBrother, mode) {
        case (false, .nativeText):
            let document = ReceiptDocument.build(receipt, columns: options.textColumns)
            transport.send(PrintJobBuilder.segments(document: document, options: options))

        case (false, .rasterImage):
            do {
                let renderer = ReceiptRenderer(width: options.width.pixels, ditherMode: .floydSteinberg)
                transport.send(PrintJobBuilder.segments(bitmap: try renderer.render(receipt), options: options))
            } catch {
                reportError(String(format: NSLocalizedString("error.render", comment: ""),
                                   error.localizedDescription))
            }

        case (true, .nativeText):
            // Pas de police interne cote Brother: la meme mise en page
            // 32 colonnes est dessinee puis envoyee en image.
            print(ReceiptDocument.build(receipt, columns: DocumentRasterizer().columns))

        case (true, .rasterImage):
            brother.print(job: setup.brotherJob) { scale in
                try ReceiptRenderer().image(receipt, scale: scale)
            }
        }
    }

    func printTestPattern() {
        if isBrother {
            brother.print(job: setup.brotherJob) { scale in
                try ReceiptRenderer().testPatternImage(height: 120, scale: scale)
            }
            return
        }
        do {
            let bitmap = try ReceiptRenderer(width: options.width.pixels).testPattern(height: 120)
            transport.send(PrintJobBuilder.segments(bitmap: bitmap, options: options))
        } catch {
            reportError(String(format: NSLocalizedString("error.pattern", comment: ""),
                               error.localizedDescription))
        }
    }

    func reportError(_ message: String) {
        if isBrother {
            brother.reportError(message)
        } else {
            transport.recordLocalError(message)
        }
    }
}
