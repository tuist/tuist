import Foundation

/// Decodes base64 that arrives in pieces of any size, ignoring line breaks, such as `base64` output read from a log
/// stream.
struct Base64StreamDecoder {
    private var pending: [UInt8] = []

    mutating func decode(_ text: String) throws -> Data {
        pending.append(contentsOf: text.utf8.filter { !($0 == 10 || $0 == 13 || $0 == 32 || $0 == 9) })
        let usable = pending.count / 4 * 4
        guard usable > 0 else { return Data() }
        defer { pending.removeFirst(usable) }
        return try Self.decode(pending[..<usable])
    }

    mutating func finish() throws -> Data {
        defer { pending.removeAll() }
        return pending.isEmpty ? Data() : try Self.decode(pending[...])
    }

    private static func decode(_ bytes: ArraySlice<UInt8>) throws -> Data {
        guard let data = Data(base64Encoded: Data(bytes)) else { throw Base64StreamDecoderError.invalid }
        return data
    }
}

enum Base64StreamDecoderError: LocalizedError {
    case invalid

    var errorDescription: String? { "The sandbox sent output that is not valid base64." }
}
