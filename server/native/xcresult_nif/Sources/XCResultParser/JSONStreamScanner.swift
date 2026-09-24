import Foundation

/// Walks a JSON document on disk one value at a time, so a document far larger than memory
/// can be read with only one member or element held at once. It knows just enough JSON to find
/// where a value ends (strings, escapes and nesting); each value's bytes are handed to
/// `JSONDecoder` as they are.
struct JSONStreamScanner {
    enum ScanError: Error, LocalizedError {
        case unexpectedByte(UInt8, offset: Int)
        case unexpectedEnd

        var errorDescription: String? {
            switch self {
            case let .unexpectedByte(byte, offset):
                "Unexpected byte 0x\(String(byte, radix: 16)) at offset \(offset) in a JSON document"
            case .unexpectedEnd:
                "The JSON document ended early"
            }
        }
    }

    fileprivate final class Reader {
        private let handle: FileHandle
        private var buffer: [UInt8] = []
        private var index = 0
        private(set) var offset = 0
        private let chunkSize: Int

        init(url: URL, chunkSize: Int) throws {
            handle = try FileHandle(forReadingFrom: url)
            self.chunkSize = chunkSize
        }

        deinit { try? handle.close() }

        func peek() throws -> UInt8? {
            if index >= buffer.count {
                // Drained per chunk: the read returns an autoreleased buffer, and nothing else
                // drains the pool during a scan that never yields.
                let next = try autoreleasepool {
                    try handle.read(upToCount: chunkSize).map { [UInt8]($0) }
                }
                guard let next, !next.isEmpty else { return nil }
                buffer = next
                index = 0
            }
            return buffer[index]
        }

        func next() throws -> UInt8? {
            guard let byte = try peek() else { return nil }
            index += 1
            offset += 1
            return byte
        }

        /// Copies the bytes of a nested value (from its opening brace or bracket to the matching
        /// close) into `data`, or only skips over them when `data` is nil, scanning each buffered
        /// chunk in one pass rather than a byte at a time: the archive's line arrays are the bulk
        /// of the document.
        func copyNestedValue(into data: inout Data?) throws {
            var depth = 0
            var inString = false
            var escaped = false
            while try peek() != nil {
                let start = index
                var i = index
                let count = buffer.count
                while i < count {
                    let byte = buffer[i]
                    i += 1
                    if inString {
                        if escaped {
                            escaped = false
                        } else if byte == 0x5C {
                            escaped = true
                        } else if byte == 0x22 {
                            inString = false
                        }
                        continue
                    }
                    switch byte {
                    case 0x22: inString = true
                    case 0x7B, 0x5B: depth += 1
                    case 0x7D, 0x5D:
                        depth -= 1
                        if depth == 0 {
                            data?.append(contentsOf: buffer[start ..< i])
                            offset += i - start
                            index = i
                            return
                        }
                    default: break
                    }
                }
                data?.append(contentsOf: buffer[start ..< i])
                offset += i - start
                index = i
            }
            throw ScanError.unexpectedEnd
        }
    }

    private let reader: Reader

    init(url: URL, chunkSize: Int = 1 << 20) throws {
        reader = try Reader(url: url, chunkSize: chunkSize)
    }

    /// Calls `body` with each member of the document's top-level object: its key and the raw
    /// bytes of its value.
    static func forEachMember(
        ofObjectAt url: URL,
        chunkSize: Int = 1 << 20,
        _ body: (_ key: String, _ value: Data) throws -> Void
    ) throws {
        let scanner = try JSONStreamScanner(url: url, chunkSize: chunkSize)
        try scanner.expect(UInt8(ascii: "{"))
        try scanner.members { key, value in try body(key, value) }
    }

    /// Calls `body` with each member of the document's top-level object and where its value
    /// sits in the file (byte offset and length), without copying the value: an index to read
    /// members back later with ``value(at:length:in:)``.
    static func forEachMemberLocation(
        ofObjectAt url: URL,
        chunkSize: Int = 1 << 20,
        _ body: (_ key: String, _ offset: Int, _ length: Int) throws -> Void
    ) throws {
        let scanner = try JSONStreamScanner(url: url, chunkSize: chunkSize)
        try scanner.expect(UInt8(ascii: "{"))
        try scanner.members(capturing: { _ in false }) { key, _ in
            let start = scanner.reader.offset
            try scanner.skipValue()
            try body(key, start, scanner.reader.offset - start)
        }
    }

    /// The bytes of a value located by ``forEachMemberLocation(ofObjectAt:chunkSize:_:)``.
    static func value(at offset: Int, length: Int, in url: URL) throws -> Data {
        try autoreleasepool {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: length).map { Data($0) } ?? Data()
        }
    }

    /// Calls `body` with the raw bytes of each element of the array under `key` in the
    /// document's top-level object. Other members are skipped.
    static func forEachElement(
        ofArrayAt key: String,
        in url: URL,
        chunkSize: Int = 1 << 20,
        _ body: (_ element: Data) throws -> Void
    ) throws {
        let scanner = try JSONStreamScanner(url: url, chunkSize: chunkSize)
        try scanner.expect(UInt8(ascii: "{"))
        try scanner.members(capturing: { _ in false }) { memberKey, _ in
            guard memberKey == key else {
                try scanner.skipValue()
                return
            }
            try scanner.expect(UInt8(ascii: "["))
            try scanner.elements(body)
        }
    }

    /// Iterates `{ "key": value, ... }` after the opening brace. Members whose key `capturing`
    /// rejects are handed to `body` without their value, positioned right at it, for the caller
    /// to consume itself.
    private func members(
        capturing: (String) -> Bool = { _ in true },
        _ body: (String, Data) throws -> Void
    ) throws {
        while true {
            try skipWhitespace()
            guard let byte = try reader.peek() else { throw ScanError.unexpectedEnd }
            if byte == UInt8(ascii: "}") {
                _ = try reader.next()
                return
            }
            let key = try string()
            try skipWhitespace()
            try expect(UInt8(ascii: ":"))
            try skipWhitespace()
            if capturing(key) {
                try body(key, try value())
            } else {
                try body(key, Data())
            }
            try skipWhitespace()
            guard let separator = try reader.next() else { throw ScanError.unexpectedEnd }
            switch separator {
            case UInt8(ascii: ","): continue
            case UInt8(ascii: "}"): return
            default: throw ScanError.unexpectedByte(separator, offset: reader.offset)
            }
        }
    }

    /// Iterates `[ value, ... ]` after the opening bracket.
    private func elements(_ body: (Data) throws -> Void) throws {
        while true {
            try skipWhitespace()
            guard let byte = try reader.peek() else { throw ScanError.unexpectedEnd }
            if byte == UInt8(ascii: "]") {
                _ = try reader.next()
                return
            }
            try body(try value())
            try skipWhitespace()
            guard let separator = try reader.next() else { throw ScanError.unexpectedEnd }
            switch separator {
            case UInt8(ascii: ","): continue
            case UInt8(ascii: "]"): return
            default: throw ScanError.unexpectedByte(separator, offset: reader.offset)
            }
        }
    }

    private func value() throws -> Data {
        try value(copying: true) ?? Data()
    }

    private func skipValue() throws {
        _ = try value(copying: false)
    }

    /// Copies the bytes of the next value: an object or array to its matching close, a string
    /// to its closing quote, or a scalar up to the next delimiter. Only consumes them when not
    /// copying.
    private func value(copying: Bool) throws -> Data? {
        var data: Data? = copying ? Data() : nil
        guard let first = try reader.peek() else { throw ScanError.unexpectedEnd }

        switch first {
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            try reader.copyNestedValue(into: &data)
            return data

        case UInt8(ascii: "\""):
            let quote = try reader.next()!
            data?.append(quote)
            var escaped = false
            while let byte = try reader.next() {
                data?.append(byte)
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    return data
                }
            }
            throw ScanError.unexpectedEnd

        default:
            while let byte = try reader.peek() {
                if byte == UInt8(ascii: ",") || byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]")
                    || byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
                    || byte == UInt8(ascii: "\t")
                {
                    return data
                }
                let scalar = try reader.next()!
                data?.append(scalar)
            }
            return data
        }
    }

    private func string() throws -> String {
        let raw = try value()
        guard raw.first == UInt8(ascii: "\"") else {
            throw ScanError.unexpectedByte(raw.first ?? 0, offset: reader.offset)
        }
        return try JSONDecoder().decode(String.self, from: raw)
    }

    private func skipWhitespace() throws {
        while let byte = try reader.peek(),
              byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
              || byte == UInt8(ascii: "\t")
        {
            _ = try reader.next()
        }
    }

    private func expect(_ expected: UInt8) throws {
        try skipWhitespace()
        guard let byte = try reader.next() else { throw ScanError.unexpectedEnd }
        guard byte == expected else { throw ScanError.unexpectedByte(byte, offset: reader.offset) }
    }
}
