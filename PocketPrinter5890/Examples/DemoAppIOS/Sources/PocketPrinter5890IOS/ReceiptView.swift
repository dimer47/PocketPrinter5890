import PocketPrinter5890BLE
import PocketPrinter5890Kit
import SwiftUI

struct ReceiptView: View {
    @ObservedObject var transport: PocketPrinter5890BLE
    @Binding var options: PrintOptions
    @State private var receipt = Receipt.sample

    var body: some View {
        List {
            Section("editor.title") {
                TextField("editor.merchant", text: $receipt.merchantName)
                TextField("editor.address", text: $receipt.address)
                DatePicker("editor.date", selection: $receipt.date)
            }

            Section("editor.items") {
                ForEach($receipt.items) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("editor.item", text: $item.name)
                        HStack {
                            Stepper("\(item.quantity)", value: $item.quantity, in: 1...99)
                                .fixedSize()
                            Spacer()
                            TextField("editor.price", value: $item.unitPrice, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                        }
                    }
                }
                .onDelete { receipt.items.remove(atOffsets: $0) }

                Button("editor.add") {
                    receipt.items.append(ReceiptItem(name: "Article", quantity: 1, unitPrice: 1))
                }
                Button("editor.reset") { receipt = .sample }
            }

            Section {
                TextField("editor.footer", text: $receipt.footer)
            }

            Section("preview.section") {
                ReceiptPreview(receipt: receipt, width: options.width.pixels)
                    .frame(maxWidth: .infinity)
            }

            Section {
                Button("print.receipt") { printReceipt() }
                    .disabled(!transport.isConnected)
            }
        }
        .navigationTitle("tab.receipt")
    }

    private func printReceipt() {
        do {
            let renderer = ReceiptRenderer(
                width: options.width.pixels,
                ditherMode: .floydSteinberg
            )
            let bitmap = try renderer.render(receipt)
            transport.send(PrintJobBuilder.segments(bitmap: bitmap, options: options))
        } catch {
            transport.recordLocalError(
                String(format: NSLocalizedString("error.render", comment: ""),
                       error.localizedDescription)
            )
        }
    }
}

/// Rendu reel du ticket, identique a ce qui sera imprime.
struct ReceiptPreview: View {
    let receipt: Receipt
    let width: Int

    var body: some View {
        Group {
            if let image = rendered {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .background(Color.white)
                    .border(Color.secondary.opacity(0.3))
            } else {
                Color.white.frame(height: 120)
            }
        }
    }

    private var rendered: CGImage? {
        try? ReceiptRenderer(width: width).previewImage(receipt)
    }
}
