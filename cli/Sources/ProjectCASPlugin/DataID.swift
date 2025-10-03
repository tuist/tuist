import Foundation
import Crypto
import SWBUtil

public struct DataID: Equatable, Hashable, Sendable {
    public let hash: String

    public init(hash: String) {
        self.hash = hash.lowercased()
    }

    public init(from data: ByteString) {
        let digest = SHA256.hash(data: data.bytes)
        self.hash = DataID.hexString(from: digest)
    }

    public var shortID: String {
        String(hash.prefix(12))
    }

    public func digestBytes() throws -> [UInt8] {
        try DataID.digestBytes(fromHex: hash)
    }

    public init(digestBytes: some Sequence<UInt8>) {
        self.hash = DataID.hexString(from: digestBytes)
    }

    public init(digestPointer: UnsafePointer<UInt8>, count: Int) {
        let buffer = UnsafeBufferPointer(start: digestPointer, count: count)
        self.hash = DataID.hexString(validating: buffer)
    }

    public static func hexString(from digest: some Sequence<UInt8>) -> String {
        let bytes = Array(digest)
        var result = String()
        result.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            result.append(Self.hexAlphabet[Int(byte >> 4)])
            result.append(Self.hexAlphabet[Int(byte & 0x0F)])
        }
        return result
    }

    public static func digestBytes(fromHex hex: String) throws -> [UInt8] {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count % 2 == 0 else {
            throw DataIDError.invalidHexString(normalized)
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(normalized.count / 2)

        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            let slice = normalized[index..<nextIndex]
            guard let value = UInt8(slice, radix: 16) else {
                throw DataIDError.invalidHexString(normalized)
            }
            bytes.append(value)
            index = nextIndex
        }

        return bytes
    }

    private static func hexString(validating bytes: UnsafeBufferPointer<UInt8>) -> String {
        var result = String()
        result.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            result.append(Self.hexAlphabet[Int(byte >> 4)])
            result.append(Self.hexAlphabet[Int(byte & 0x0F)])
        }
        return result
    }

    private static let hexAlphabet: [Character] = Array("0123456789abcdef")
}

public enum DataIDError: Error, CustomStringConvertible {
    case invalidHexString(String)

    public var description: String {
        switch self {
        case .invalidHexString(let value):
            return "Invalid hex digest: \(value)"
        }
    }
}

extension DataID: CustomStringConvertible {
    public var description: String {
        hash
    }
}

extension DataID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self.hash = raw.lowercased()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hash)
    }
}
