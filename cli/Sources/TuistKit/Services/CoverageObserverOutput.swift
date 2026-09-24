import CryptoKit
import Foundation

/// What the coverage observer (`cli/CoverageObserver/TuistCoverageObserver.m`) wrote for one test
/// process: the instrumented images with the sections that name their functions, and one record
/// per scope with the coverage counters that moved in it.
struct CoverageObserverOutput {
    enum RecordKind: UInt8 {
        case gap = 0
        case xctest = 1
        case swiftTesting = 2
    }

    struct Record: Equatable {
        var kind: RecordKind
        var overlapped: Bool
        var module: String
        var suite: String
        var name: String
        /// Counter indices per image index.
        var counters: [Int: [UInt32]]
        /// How much each of `counters` moved, in the same order; empty for an observer that
        /// does not report it.
        var deltas: [Int: [UInt64]] = [:]
    }

    struct Image {
        var path: String
        /// The function each counter belongs to, by counter index; nil where no record claims it.
        var functionByCounter: [String?]
        /// The counters each function owns, ascending by first counter.
        var functions: [FunctionCounters] = []
    }

    var images: [Int: Image]
    var records: [Record]

    init(images: [Int: Image], records: [Record]) {
        self.images = images
        self.records = records
    }

    init(directory: URL) throws {
        var images: [Int: Image] = [:]
        let table = try String(contentsOf: directory.appendingPathComponent("images.tsv"), encoding: .utf8)
        for line in table.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5,
                  let index = Int(fields[0]),
                  let countersSize = Int(fields[1]),
                  let dataAddress = UInt64(fields[2]),
                  let countersAddress = UInt64(fields[3])
            else { continue }
            let data = try Data(contentsOf: directory.appendingPathComponent("\(index).data"))
            let names = (try? Data(contentsOf: directory.appendingPathComponent("\(index).names"))) ?? Data()
            let functions = Self.functionCounters(
                data: data, dataAddress: dataAddress, countersAddress: countersAddress, countersSize: countersSize
            )
            images[index] = Image(
                path: String(fields[4]),
                functionByCounter: Self.functionByCounter(
                    functions: functions, names: Self.parseNames(names), countersSize: countersSize
                ),
                functions: functions.sorted { $0.first < $1.first }
            )
        }
        self.images = images
        records = Self.parseRecords(try Data(contentsOf: directory.appendingPathComponent("records.bin")))
    }

    /// The functions a record's counters belong to, per image path.
    func functions(of record: Record) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for (imageIndex, counters) in record.counters {
            guard let image = images[imageIndex] else { continue }
            for counter in counters {
                let index = Int(counter)
                guard index < image.functionByCounter.count, let function = image.functionByCounter[index] else { continue }
                result[image.path, default: []].insert(function)
            }
        }
        return result
    }

    // MARK: - Records

    /// See `write_record()` in the observer. A truncated tail (a process killed mid-write) ends
    /// the list at the last whole record.
    static func parseRecords(_ data: Data) -> [Record] {
        var reader = ByteReader(data)
        var records: [Record] = []
        while !reader.isAtEnd {
            guard let kindByte = reader.u8(), let flags = reader.u8(), let version = reader.u8(), reader.u8() != nil,
                  let module = reader.string(), let suite = reader.string(), let name = reader.string(),
                  let imageCount = reader.u32()
            else { break }
            var counters: [Int: [UInt32]] = [:]
            var deltas: [Int: [UInt64]] = [:]
            var complete = true
            for _ in 0 ..< imageCount {
                guard let index = reader.u32(), let count = reader.u32(), let indices = reader.u32Array(Int(count)) else {
                    complete = false
                    break
                }
                counters[Int(index)] = indices
                if version >= 1 {
                    guard let moved = reader.u64Array(Int(count)) else {
                        complete = false
                        break
                    }
                    deltas[Int(index)] = moved
                }
            }
            guard complete, let kind = RecordKind(rawValue: kindByte) else { break }
            records.append(Record(
                kind: kind, overlapped: flags & 1 == 1, module: module, suite: suite, name: name, counters: counters,
                deltas: deltas
            ))
        }
        return records
    }

    // MARK: - LLVM profile sections

    /// `__llvm_prf_names`: repeated `[uleb128 uncompressed size][uleb128 compressed size][bytes]`,
    /// the bytes zlib-compressed when the compressed size is not zero, holding names separated
    /// by `0x01`.
    static func parseNames(_ data: Data) -> [String] {
        var reader = ByteReader(data)
        var names: [String] = []
        while !reader.isAtEnd {
            guard let uncompressed = reader.uleb128(), let compressed = reader.uleb128() else { break }
            let chunk: Data?
            if compressed > 0 {
                chunk = reader.bytes(Int(compressed)).flatMap { Self.inflate($0) }
            } else {
                chunk = reader.bytes(Int(uncompressed))
            }
            guard let chunk else { break }
            names += chunk.split(separator: 0x01).compactMap { String(data: Data($0), encoding: .utf8) }
        }
        return names
    }

    /// The key `__llvm_prf_data` refers to a name by: the low 64 bits of its MD5, little endian.
    static func nameReference(_ name: String) -> UInt64 {
        let digest = Array(Insecure.MD5.hash(data: Data(name.utf8)))
        return digest.prefix(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
    }

    /// The counters one function owns: `count` of them from `first`, in the image's counters
    /// section. `reference` and `hash` are what the coverage mapping knows the function by.
    struct FunctionCounters: Equatable {
        var reference: UInt64
        var hash: UInt64
        var first: Int
        var count: Int
    }

    /// `__llvm_prf_data` is an array of fixed-size records: `u64 NameRef, u64 FuncHash,
    /// iptr CounterPtr, …, u32 NumCounters` at a layout that changed across LLVM versions (a
    /// bitmap pointer was added, and the counter pointer became relative to the record). Each
    /// known layout is tried and the one whose records land inside the counters section wins.
    static func functionCounters(
        data: Data,
        dataAddress: UInt64,
        countersAddress: UInt64,
        countersSize: Int
    ) -> [FunctionCounters] {
        let totalCounters = countersSize / 8
        let layouts: [(recordSize: Int, countOffset: Int)] = [(64, 48), (56, 40), (48, 40)]
        for layout in layouts where data.count % layout.recordSize == 0 && !data.isEmpty {
            for relative in [true, false] {
                var result: [FunctionCounters] = []
                var claimed = 0
                var valid = true
                for record in 0 ..< data.count / layout.recordSize {
                    let offset = record * layout.recordSize
                    let counterPointer = Int64(bitPattern: data.load(at: offset + 16) as UInt64)
                    let count = Int(data.load(at: offset + layout.countOffset) as UInt32)
                    if count == 0, counterPointer == 0 { continue }
                    let address = relative
                        ? Int64(bitPattern: dataAddress) + Int64(offset) + counterPointer
                        : counterPointer
                    let distance = address - Int64(bitPattern: countersAddress)
                    guard distance >= 0, distance % 8 == 0, count <= 1 << 24 else { valid = false; break }
                    let first = Int(distance / 8)
                    guard first + count <= totalCounters else { valid = false; break }
                    result.append(FunctionCounters(
                        reference: data.load(at: offset), hash: data.load(at: offset + 8), first: first, count: count
                    ))
                    claimed += count
                }
                if valid, claimed > 0, claimed * 2 >= totalCounters { return result }
            }
        }
        return []
    }

    static func functionByCounter(functions: [FunctionCounters], names: [String], countersSize: Int) -> [String?] {
        var byReference: [UInt64: String] = [:]
        for name in names {
            byReference[nameReference(name)] = name
        }
        var result: [String?] = Array(repeating: nil, count: countersSize / 8)
        for function in functions {
            let name = byReference[function.reference]
            for counter in function.first ..< function.first + function.count {
                result[counter] = name
            }
        }
        return result
    }

    /// zlib stream (two header bytes, then raw DEFLATE, which is what Foundation inflates).
    static func inflate(_ data: Data) -> Data? {
        guard data.count > 2 else { return nil }
        return try? (data.dropFirst(2) as NSData).decompressed(using: .zlib) as Data
    }
}

struct ByteReader {
    private let data: Data
    private(set) var position: Int

    init(_ data: Data) {
        self.data = data
        position = data.startIndex
    }

    var isAtEnd: Bool { position >= data.endIndex }

    mutating func u8() -> UInt8? {
        guard position < data.endIndex else { return nil }
        defer { position += 1 }
        return data[position]
    }

    mutating func u32() -> UInt32? {
        guard position + 4 <= data.endIndex else { return nil }
        defer { position += 4 }
        return data.load(at: position - data.startIndex)
    }

    mutating func u32Array(_ count: Int) -> [UInt32]? {
        guard count >= 0, position + count * 4 <= data.endIndex else { return nil }
        return (0 ..< count).compactMap { _ in u32() }
    }

    mutating func u64Array(_ count: Int) -> [UInt64]? {
        guard count >= 0, position + count * 8 <= data.endIndex else { return nil }
        defer { position += count * 8 }
        return (0 ..< count).map { data.load(at: position - data.startIndex + $0 * 8) }
    }

    mutating func bytes(_ count: Int) -> Data? {
        guard count >= 0, position + count <= data.endIndex else { return nil }
        defer { position += count }
        return data.subdata(in: position ..< position + count)
    }

    mutating func string() -> String? {
        guard let length = u32(), let bytes = bytes(Int(length)) else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    mutating func uleb128() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while let byte = u8() {
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }
}

extension Data {
    func load<T: FixedWidthInteger>(at offset: Int) -> T {
        var value: T = 0
        let start = startIndex + offset
        guard offset >= 0, start + MemoryLayout<T>.size <= endIndex else { return 0 }
        Swift.withUnsafeMutableBytes(of: &value) { $0.copyBytes(from: self[start ..< start + MemoryLayout<T>.size]) }
        return T(littleEndian: value)
    }
}
