import Foundation

public enum BLEPacketizer {
    public static func chunks(_ bytes: [UInt8], maxWriteLength: Int) -> [[UInt8]] {
        precondition(maxWriteLength > 0)
        var result: [[UInt8]] = []
        var index = 0
        while index < bytes.count {
            let end = min(index + maxWriteLength, bytes.count)
            result.append(Array(bytes[index..<end]))
            index = end
        }
        return result
    }
}
