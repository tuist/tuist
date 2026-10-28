import Crypto
import Foundation

/// FastCDC 2020 content-defined chunking with the parameters a cache advertises for `SpliceBlob`: 128 KiB
/// minimum, 512 KiB average and 2 MiB maximum chunks at normalization level 2 and seed 0. Cut points match the
/// `fastcdc` crate's `v2020` chunker, so the chunks of a blob are the ones other clients of the cache publish.
enum REAPIChunking {
    static let minimumChunkBytes = 128 * 1024
    static let averageChunkBytes = 512 * 1024
    static let maximumChunkBytes = 2 * 1024 * 1024
    /// The most chunks a cache accepts in one blob's recipe.
    static let maximumChunks = 16384

    struct Chunk: Sendable, Equatable {
        let offset: Int64
        let digest: REAPI.Digest
    }

    /// Splits the file into chunks, failing when its content no longer matches `digest`. The cut function never
    /// looks further than the largest chunk, so the file is read through a window instead of loaded whole.
    static func chunks(of file: URL, digest: REAPI.Digest) throws -> [Chunk] {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var buffer: [UInt8] = []
        var start = 0
        var exhausted = false
        var offset: Int64 = 0
        var whole = SHA256()
        var chunks: [Chunk] = []
        // The tables are read once per byte, so the loop indexes them through pointers rather than the static arrays.
        let gear = UnsafeMutableBufferPointer<UInt64>.allocate(capacity: 256)
        let gearShifted = UnsafeMutableBufferPointer<UInt64>.allocate(capacity: 256)
        defer {
            gear.deallocate()
            gearShifted.deallocate()
        }
        _ = gear.initialize(from: Self.gear)
        _ = gearShifted.initialize(from: Self.gear.map { $0 << 1 })
        while true {
            while !exhausted, buffer.count - start < maximumChunkBytes {
                if start > 0 {
                    buffer.removeFirst(start)
                    start = 0
                }
                let data = try handle.read(upToCount: 2 * maximumChunkBytes) ?? Data()
                if data.isEmpty { exhausted = true } else { buffer.append(contentsOf: data) }
            }
            if start == buffer.count { break }
            let chunk = buffer.withUnsafeBufferPointer { pointer in
                let length = cut(UnsafeBufferPointer(rebasing: pointer[start...]), gear: gear, gearShifted: gearShifted)
                let bytes = UnsafeRawBufferPointer(UnsafeBufferPointer(rebasing: pointer[start ..< start + length]))
                whole.update(bufferPointer: bytes)
                return Chunk(offset: offset, digest: .with {
                    $0.hash = REAPI.hashString(SHA256.hash(data: bytes))
                    $0.sizeBytes = Int64(length)
                })
            }
            chunks.append(chunk)
            offset += chunk.digest.sizeBytes
            start += Int(chunk.digest.sizeBytes)
        }
        guard offset == digest.sizeBytes, REAPI.hashString(whole.finalize()) == digest.hash else {
            throw REAPICacheError.corruptBlob
        }
        return chunks
    }

    /// The length of the chunk that starts `source`, given the gear table and the table shifted left by one bit.
    static func cut(
        _ source: UnsafeBufferPointer<UInt8>,
        gear: UnsafeMutableBufferPointer<UInt64>,
        gearShifted: UnsafeMutableBufferPointer<UInt64>
    ) -> Int {
        let smallMask = Self.smallMask, smallMaskShifted = Self.smallMask << 1
        let largeMask = Self.largeMask, largeMaskShifted = Self.largeMask << 1
        var remaining = source.count
        if remaining <= minimumChunkBytes { return remaining }
        var center = averageChunkBytes
        if remaining > maximumChunkBytes {
            remaining = maximumChunkBytes
        } else if remaining < center {
            center = remaining
        }
        var index = minimumChunkBytes / 2
        var hash: UInt64 = 0
        while index < center / 2 {
            let position = index * 2
            hash = (hash << 2) &+ gearShifted[Int(source[position])]
            if hash & smallMaskShifted == 0 { return position }
            hash = hash &+ gear[Int(source[position + 1])]
            if hash & smallMask == 0 { return position + 1 }
            index += 1
        }
        while index < remaining / 2 {
            let position = index * 2
            hash = (hash << 2) &+ gearShifted[Int(source[position])]
            if hash & largeMaskShifted == 0 { return position }
            hash = hash &+ gear[Int(source[position + 1])]
            if hash & largeMask == 0 { return position + 1 }
            index += 1
        }
        return remaining
    }

    /// Masks for 2^(19 + 2) and 2^(19 - 2) bits: the average chunk size's bits, normalized at level 2.
    private static let smallMask: UInt64 = 0x0000_D917_6753_7000
    private static let largeMask: UInt64 = 0x0000_D907_0353_7000
    /// The gear table: one pseudo-random value per byte, entry `i` being the first eight bytes, big-endian, of the MD5
    /// of 64 bytes equal to `i`. This is how the `fastcdc` crate derives its table, so cut points match other clients.
    private static let gear: [UInt64] = (0 ... UInt8.max).map { byte in
        Insecure.MD5.hash(data: Data(repeating: byte, count: 64)).prefix(8).reduce(0) { $0 << 8 | UInt64($1) }
    }
}
