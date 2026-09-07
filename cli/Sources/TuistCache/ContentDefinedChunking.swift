import Crypto
import Foundation

/// FastCDC 2020 with normalization level 2, a 512 KiB average, and seed 0.
/// https://github.com/bazelbuild/remote-apis/blob/main/build/bazel/remote/execution/v2/remote_execution.proto
enum ContentDefinedChunking {
    static let maximumBytes = 2 * 1024 * 1024
    private static let minimumBytes = 128 * 1024
    private static let averageBytes = 512 * 1024
    private static let gear: [UInt64] = (0 ... 255).map { value in
        // This reproduces the algorithm's table, not a content integrity hash.
        Insecure.MD5.hash(data: Data(repeating: UInt8(value), count: 64)).prefix(8)
            .reduce(0) { ($0 << 8) | UInt64($1) }
    }

    struct Digest: Codable, Hashable, Sendable {
        let hash: String
        let size: Int
    }

    struct Chunk: Sendable {
        let digest: Digest
        let offset: UInt64
    }

    struct Artifact: Sendable {
        let digest: Digest
        let chunks: [Chunk]
    }

    static func digest(_ data: Data) -> Digest {
        Digest(hash: hex(SHA256.hash(data: data)), size: data.count)
    }

    /// A single deflated binary has no independent compression histories to
    /// reuse. Inspect the archive directory without extracting customer files.
    static func hasReusableArchiveEntries(_ url: URL) throws -> Bool {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        guard try input.read(upToCount: 4) == Data([0x50, 0x4B, 0x03, 0x04]) else { return true }
        let size = try input.seekToEnd()
        let tailSize = min(size, 65557)
        try input.seek(toOffset: size - tailSize)
        let tail = [UInt8](try input.read(upToCount: Int(tailSize)) ?? Data())
        guard tail.count >= 22 else { return false }
        func number(_ bytes: [UInt8], _ offset: Int, _ length: Int) -> UInt64 {
            (0 ..< length).reduce(0) { $0 | (UInt64(bytes[offset + $1]) << ($1 * 8)) }
        }
        guard let end = stride(from: tail.count - 22, through: 0, by: -1).first(where: {
            number(tail, $0, 4) == 0x0605_4B50 && $0 + 22 + Int(number(tail, $0 + 20, 2)) == tail.count
        }) else { return false }
        let entries = number(tail, end + 10, 2)
        let directorySize = number(tail, end + 12, 4)
        var offset = number(tail, end + 16, 4)
        // Unknown or extended layouts use the original uploader unchanged.
        guard entries < 65535, offset + directorySize <= size,
              number(tail, end + 4, 4) == 0 else { return false }
        let directoryEnd = offset + directorySize
        var independentEntries = 0
        for _ in 0 ..< entries {
            guard offset + 46 <= directoryEnd else { return false }
            try input.seek(toOffset: offset)
            let header = [UInt8](try input.read(upToCount: 46) ?? Data())
            guard header.count == 46, number(header, 0, 4) == 0x0201_4B50 else { return false }
            let compressedSize = number(header, 20, 4)
            let method = number(header, 10, 2)
            if method == 0, compressedSize >= maximumBytes { return true }
            if compressedSize >= minimumBytes { independentEntries += 1 }
            offset += 46 + number(header, 28, 2) + number(header, 30, 2) + number(header, 32, 2)
        }
        return independentEntries >= 2
    }

    static func cut(_ bytes: UnsafeBufferPointer<UInt8>) -> Int {
        guard bytes.count > minimumBytes else { return bytes.count }
        let end = min(bytes.count, maximumBytes)
        let center = min(end, averageBytes)
        var index = minimumBytes / 2
        var hash: UInt64 = 0
        while index < end / 2 {
            let offset = index * 2
            let mask: UInt64 = offset < center / 2 * 2 ? 0x0000_D917_6753_7000 : 0x0000_D907_0353_7000
            hash = (hash << 2) &+ (gear[Int(bytes[offset])] << 1)
            if hash & (mask << 1) == 0 { return offset }
            hash = hash &+ gear[Int(bytes[offset + 1])]
            if hash & mask == 0 { return offset + 1 }
            index += 1
        }
        return end
    }

    static func scan(_ url: URL, onChunk: ((Digest, Data) -> Void)? = nil) throws -> Artifact {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var buffer = Data()
        var hasher = SHA256()
        var chunks: [Chunk] = []
        var offset: UInt64 = 0
        var ended = false
        while true {
            while !ended, buffer.count < maximumBytes {
                let bytes = try input.read(upToCount: maximumBytes - buffer.count) ?? Data()
                ended = bytes.isEmpty
                buffer.append(bytes)
            }
            guard !buffer.isEmpty else { break }
            let length = buffer.withUnsafeBytes { cut($0.bindMemory(to: UInt8.self)) }
            let bytes = Data(buffer.prefix(length))
            hasher.update(data: bytes)
            let digest = digest(bytes)
            chunks.append(Chunk(digest: digest, offset: offset))
            onChunk?(digest, bytes)
            guard chunks.count <= 16384 else { throw ChunkedModuleCacheUploadError.tooManyChunks }
            offset += UInt64(length)
            buffer = Data(buffer.dropFirst(length))
        }
        return Artifact(digest: Digest(hash: hex(hasher.finalize()), size: Int(offset)), chunks: chunks)
    }

    private static func hex(_ digest: some Sequence<UInt8>) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
