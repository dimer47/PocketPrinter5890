import Foundation

public enum Hex {
    public static func encode(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public static func encode(_ data: Data) -> String {
        encode(Array(data))
    }
}
