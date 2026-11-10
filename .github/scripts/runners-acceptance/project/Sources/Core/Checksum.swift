import Foundation

public struct Checksum: Hashable, Sendable {
    public let value: UInt64

    public init(_ bytes: some Sequence<UInt8>) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        value = hash
    }

    public var hex: String {
        String(value, radix: 16)
    }
}
