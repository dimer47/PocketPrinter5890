import Foundation

public struct ReceiptItem: Identifiable, Equatable {
    public let id = UUID()
    public var name: String
    public var quantity: Int
    public var unitPrice: Decimal

    public var total: Decimal {
        unitPrice * Decimal(quantity)
    }

    public init(name: String, quantity: Int, unitPrice: Decimal) {
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
    }
}

public struct Receipt: Equatable {
    public var merchantName: String
    public var address: String
    public var date: Date
    public var items: [ReceiptItem]
    public var footer: String

    public var total: Decimal {
        items.reduce(0) { $0 + $1.total }
    }

    public init(merchantName: String, address: String, date: Date, items: [ReceiptItem], footer: String) {
        self.merchantName = merchantName
        self.address = address
        self.date = date
        self.items = items
        self.footer = footer
    }

    public static let sample = Receipt(
        merchantName: "LIDL TEST",
        address: "Ticket 58 mm - 384 px",
        date: Date(timeIntervalSince1970: 1_720_000_000),
        items: [
            ReceiptItem(name: "Cafe", quantity: 1, unitPrice: 2.49),
            ReceiptItem(name: "Pain", quantity: 2, unitPrice: 1.20),
            ReceiptItem(name: "Remise", quantity: 1, unitPrice: -0.50)
        ],
        footer: "Merci"
    )
}
