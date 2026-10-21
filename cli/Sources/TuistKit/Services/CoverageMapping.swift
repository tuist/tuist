import CryptoKit
import Foundation
import MachO

/// An instrumented image's coverage mapping: for every function, the source regions its counters
/// stand for (`__llvm_covfun`, with the file names in `__llvm_covmap`). With the counts a scope
/// moved, it tells which lines ran in it, by the rules `llvm-cov` reports lines with, so a test's
/// lines and the run's report agree.
///
/// The format belongs to LLVM and moves with it; `TestCoverageEvidenceService` checks what is
/// decoded here against `llvm-cov`'s own report of the same image before relying on it.
struct CoverageMapping {
    enum RegionKind: UInt8 {
        case code = 0
        case expansion = 1
        case skipped = 2
        case gap = 3
        case branch = 4
    }

    /// A counter as the mapping encodes it: nothing, one of the function's counters, or an
    /// expression over two others.
    enum Counter: Equatable {
        case zero
        case reference(Int)
        case subtract(Int)
        case add(Int)

        init(encoded: UInt64) {
            let value = Int(encoded >> 2)
            switch encoded & 3 {
            case 1: self = .reference(value)
            case 2: self = .subtract(value)
            case 3: self = .add(value)
            default: self = .zero
            }
        }
    }

    struct Region: Equatable {
        var kind: RegionKind
        var counter: Counter
        var lineStart: Int
        var columnStart: Int
        var lineEnd: Int
        var columnEnd: Int
    }

    struct Function {
        var reference: UInt64
        var hash: UInt64
        var expressions: [(Counter, Counter)]
        /// Regions per file index into `CoverageMapping.files`.
        var regions: [(file: Int, region: Region)]
    }

    struct FunctionKey: Hashable {
        var reference: UInt64
        var hash: UInt64
    }

    private(set) var files: [String] = []
    private(set) var functions: [Function] = []
    private(set) var functionIndex: [FunctionKey: Int] = [:]
    /// The functions with a region in each file.
    private(set) var functionsByFile: [Int: [Int]] = [:]

    init(files: [String], functions: [Function]) {
        self.files = files
        for function in functions {
            let key = FunctionKey(reference: function.reference, hash: function.hash)
            guard functionIndex[key] == nil else { continue }
            functionIndex[key] = self.functions.count
            for file in Set(function.regions.map(\.file)) {
                functionsByFile[file, default: []].append(self.functions.count)
            }
            self.functions.append(function)
        }
    }

    /// The same mapping with each file's path transformed: what maps the aliases Xcode's prefix
    /// mapping recorded back to this build's directories.
    func remappingFiles(_ transform: (String) -> String) -> CoverageMapping {
        var mapping = self
        mapping.files = files.map(transform)
        return mapping
    }

    /// The mapping of the image at `path`, or nil when it has none or it cannot be read.
    init?(imagePath path: String) {
        guard let image = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { return nil }
        let sections = Self.sections(of: image, named: ["__llvm_covmap", "__llvm_covfun"])
        guard let covmap = sections["__llvm_covmap"], let covfun = sections["__llvm_covfun"] else { return nil }
        self.init(covmap: covmap, covfun: covfun)
    }

    /// The mappings of the object files in the static archive at `path` (BSD `ar`: a 60-byte
    /// header per member, a `#1/<length>` name carried in the member's data, an even-byte pad
    /// after each member), leaving out members that are not Mach-O, such as the symbol table.
    static func mappings(archivePath path: String) -> [CoverageMapping] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              let archive = archive(in: data)
        else { return [] }
        return archiveMembers(archive).compactMap { member in
            let sections = sections(of: member, named: ["__llvm_covmap", "__llvm_covfun"])
            guard let covmap = sections["__llvm_covmap"], let covfun = sections["__llvm_covfun"] else { return nil }
            return CoverageMapping(covmap: covmap, covfun: covfun)
        }
    }

    /// Whether the product at `path`, a Mach-O image or a static archive, was built with coverage,
    /// so a run that collects coverage counts its lines: it carries a coverage mapping, or, when
    /// none of its code has a body to map (a module of constants), it still names the profile
    /// runtime. Anything else, or anything unreadable, was not.
    static func isInstrumented(path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              data.count >= MemoryLayout<mach_header_64>.size
        else { return false }
        if let archive = archive(in: data) {
            return archiveMembers(archive).contains(where: isInstrumented(image:))
        }
        return isInstrumented(image: data)
    }

    /// The symbol through which an object the compiler instrumented pulls in the profile runtime:
    /// referenced by every such object, counters or not, and defined in an image linked from them.
    static let profileRuntimeSymbol = "___llvm_profile_runtime"

    private static func isInstrumented(image: Data) -> Bool {
        !sections(of: image, named: ["__llvm_covmap"]).isEmpty || namesSymbol(profileRuntimeSymbol, in: image)
    }

    // BSD `ar` (`ar.h`, which Swift does not import): `ARMAG`, `sizeof(struct ar_hdr)`, the
    // `ar_name` and `ar_size` fields, and `AR_EFMT1`, the prefix of a name carried in the member's data.
    private static let archiveMagic = Array("!<arch>\n".utf8)
    private static let archiveHeaderSize = 60
    private static let archiveNameField = 0 ..< 16
    private static let archiveSizeField = 48 ..< 58
    private static let archiveExtendedNamePrefix = "#1/"

    /// The BSD `ar` archive in `data`: the data itself, or the chosen slice of a universal file
    /// whose slices are archives, which is how Xcode packs a static framework built for several
    /// architectures. Nil for anything else.
    static func archive(in data: Data) -> Data? {
        if isArchive(data) { return data }
        guard let slice = universalSlice(of: data) else { return nil }
        let candidate = data.subdata(in: data.startIndex + slice.lowerBound ..< data.startIndex + slice.upperBound)
        return isArchive(candidate) ? candidate : nil
    }

    private static func isArchive(_ data: Data) -> Bool {
        data.prefix(archiveMagic.count).elementsEqual(archiveMagic)
    }

    /// The 64-bit Mach-O members of a BSD `ar` archive: a fixed-size text header per member, an
    /// even-byte pad after each, and the symbol table and other non-Mach-O members left out.
    static func archiveMembers(_ archive: Data) -> [Data] {
        guard isArchive(archive) else { return [] }
        var members: [Data] = []
        var offset = archiveMagic.count
        while offset + archiveHeaderSize <= archive.count {
            let header = archive.subdata(in: archive.startIndex + offset ..< archive.startIndex + offset + archiveHeaderSize)
            func field(_ range: Range<Int>) -> String {
                String(
                    decoding: header[header.startIndex + range.lowerBound ..< header.startIndex + range.upperBound],
                    as: UTF8.self
                )
                .trimmingCharacters(in: .whitespaces)
            }
            guard let size = Int(field(archiveSizeField)) else { break }
            var start = offset + archiveHeaderSize
            var length = size
            let name = field(archiveNameField)
            if name.hasPrefix(archiveExtendedNamePrefix), let nameLength = Int(name.dropFirst(archiveExtendedNamePrefix.count)) {
                start += nameLength
                length -= nameLength
            }
            guard length >= 0, start + length <= archive.count else { break }
            let member = archive.subdata(in: archive.startIndex + start ..< archive.startIndex + start + length)
            if let header: mach_header_64 = member.structure(at: 0), header.magic == MH_MAGIC_64 { members.append(member) }
            offset = (offset + archiveHeaderSize + size + 1) & ~1
        }
        return members
    }

    init?(covmap: Data, covfun: Data) {
        var indexByFile: [String: Int] = [:]
        var files: [String] = []
        var tables: [UInt64: [Int]] = [:]
        var offset = 0
        while offset + 16 <= covmap.count {
            let filenamesSize = Int(covmap.load(at: offset + 4) as UInt32)
            let coverageSize = Int(covmap.load(at: offset + 8) as UInt32)
            let version = covmap.load(at: offset + 12) as UInt32
            guard offset + 16 + filenamesSize <= covmap.count else { return nil }
            let blob = covmap.subdata(in: covmap.startIndex + offset + 16 ..< covmap.startIndex + offset + 16 + filenamesSize)
            // Version 4 (encoded as 3) moved the functions out of this section and compressed the
            // names; nothing older is produced by a toolchain Tuist supports.
            guard version >= 3, let names = Self.filenames(blob, version: version) else { return nil }
            tables[Self.reference(of: blob)] = names.map { name in
                if let index = indexByFile[name] { return index }
                indexByFile[name] = files.count
                files.append(name)
                return files.count - 1
            }
            offset = (offset + 16 + filenamesSize + coverageSize + 7) & ~7
        }

        var functions: [Function] = []
        offset = 0
        while offset + 28 <= covfun.count {
            let reference: UInt64 = covfun.load(at: offset)
            let dataSize = Int(covfun.load(at: offset + 8) as UInt32)
            let hash: UInt64 = covfun.load(at: offset + 12)
            let filenamesReference: UInt64 = covfun.load(at: offset + 20)
            guard offset + 28 + dataSize <= covfun.count else { return nil }
            let data = covfun.subdata(in: covfun.startIndex + offset + 28 ..< covfun.startIndex + offset + 28 + dataSize)
            offset = (offset + 28 + dataSize + 7) & ~7
            guard let table = tables[filenamesReference] else { continue }
            guard let function = Self.function(data, reference: reference, hash: hash, table: table) else { return nil }
            functions.append(function)
        }
        guard !functions.isEmpty else { return nil }
        self.init(files: files, functions: functions)
    }
}

// MARK: - Lines

extension CoverageMapping {
    /// The executable lines of a file and how often each ran, given each function's counter
    /// values (a function left out ran nothing). Nil for a file the mapping does not know.
    func lines(file: Int, counts: [Int: [UInt64]]) -> [Int: UInt64] {
        var regions: [CountedRegion] = []
        for functionIndex in functionsByFile[file] ?? [] {
            let function = functions[functionIndex]
            let values = counts[functionIndex] ?? []
            for entry in function.regions where entry.file == file && entry.region.kind != .branch {
                regions.append(CountedRegion(
                    region: entry.region,
                    count: values.isEmpty ? 0 : Self.evaluate(entry.region.counter, values, function.expressions)
                ))
            }
        }
        return Self.lines(segments: Self.segments(regions))
    }

    /// Counter arithmetic wraps as `llvm-cov`'s does, so an inconsistent profile reads the same
    /// here as in its report.
    static func evaluate(_ counter: Counter, _ values: [UInt64], _ expressions: [(Counter, Counter)], depth: Int = 0) -> UInt64 {
        switch counter {
        case .zero: return 0
        case let .reference(index): return index < values.count ? values[index] : 0
        case let .subtract(index), let .add(index):
            guard index < expressions.count, depth < 256 else { return 0 }
            let left = evaluate(expressions[index].0, values, expressions, depth: depth + 1)
            let right = evaluate(expressions[index].1, values, expressions, depth: depth + 1)
            if case .subtract = counter { return left &- right }
            return left &+ right
        }
    }

    struct CountedRegion {
        var region: Region
        var count: UInt64

        var start: Location { Location(line: region.lineStart, column: region.columnStart) }
        var end: Location { Location(line: region.lineEnd, column: region.columnEnd) }
    }

    struct Location: Comparable {
        var line: Int
        var column: Int

        static func < (lhs: Location, rhs: Location) -> Bool {
            (lhs.line, lhs.column) < (rhs.line, rhs.column)
        }
    }

    struct Segment: Equatable {
        var line: Int
        var column: Int
        var count: UInt64
        var hasCount: Bool
        var isRegionEntry: Bool
        var isGap: Bool
    }

    /// `llvm-cov`'s `SegmentBuilder`: the file's regions flattened into the points where the
    /// count changes, the innermost region winning.
    static func segments(_ input: [CountedRegion]) -> [Segment] {
        let sorted = input.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $1.end < $0.end }
            return $0.region.kind.rawValue < $1.region.kind.rawValue
        }
        var regions: [CountedRegion] = []
        for region in sorted {
            if let last = regions.last, last.start == region.start, last.end == region.end {
                if last.region.kind == region.region.kind {
                    regions[regions.count - 1].count &+= region.count
                } else if last.region.kind != .code, region.region.kind == .code {
                    regions[regions.count - 1] = region
                }
                continue
            }
            regions.append(region)
        }

        var segments: [Segment] = []
        var active: [CountedRegion] = []

        func start(_ region: CountedRegion, at location: Location, isRegionEntry: Bool, emitSkipped: Bool = false) {
            let hasCount = !emitSkipped && region.region.kind != .skipped
            if let last = segments.last, !isRegionEntry, !emitSkipped,
               last.hasCount == hasCount, last.count == region.count, !last.isRegionEntry
            {
                return
            }
            segments.append(Segment(
                line: location.line, column: location.column, count: hasCount ? region.count : 0, hasCount: hasCount,
                isRegionEntry: isRegionEntry, isGap: region.region.kind == .gap
            ))
        }

        func complete(until location: Location?, from first: Int) {
            let completed = active[first...].enumerated()
                .sorted { ($0.element.end, $0.offset) < ($1.element.end, $1.offset) }
                .map(\.element)
            active.replaceSubrange(first..., with: completed)
            var index = first
            while index + 1 < active.count {
                defer { index += 1 }
                var completedRegion = active[index + 1]
                let completedLocation = active[index].end
                if let location, completedLocation == location { break }
                if completedLocation == completedRegion.end { continue }
                for later in active[(index + 1)...] where completedRegion.end == later.end {
                    completedRegion = later
                }
                start(completedRegion, at: completedLocation, isRegionEntry: false)
            }
            if let last = active.last {
                if first > 0, last.end != location {
                    start(active[first - 1], at: last.end, isRegionEntry: false)
                } else if first == 0, location == nil || location != last.end {
                    start(last, at: last.end, isRegionEntry: false, emitSkipped: true)
                }
            }
            active.removeSubrange(first...)
        }

        for (index, region) in regions.enumerated() {
            let current = region.start
            let kept = active.filter { $0.end > current }
            if kept.count != active.count {
                let first = kept.count
                active = kept + active.filter { $0.end <= current }
                complete(until: current, from: first)
            }
            let isGap = region.region.kind == .gap
            if current == region.end {
                if let enclosing = active.last {
                    var inherited = region
                    inherited.region.kind = enclosing.region.kind
                    inherited.count = enclosing.count
                    start(inherited, at: current, isRegionEntry: !isGap)
                } else {
                    start(region, at: current, isRegionEntry: !isGap, emitSkipped: true)
                }
                continue
            }
            if index + 1 == regions.count || regions[index + 1].start != current {
                start(region, at: current, isRegionEntry: !isGap)
            }
            active.append(region)
        }
        if !active.isEmpty { complete(until: nil, from: 0) }
        return segments
    }

    /// `llvm-cov`'s `LineCoverageStats`: a line is executable when a region starts on it or one
    /// reaches it from above, and its count is the largest of those.
    static func lines(segments: [Segment]) -> [Int: UInt64] {
        guard let first = segments.first, let last = segments.last else { return [:] }
        var result: [Int: UInt64] = [:]
        var index = 0
        var wrapped: Segment?
        for line in first.line ... last.line {
            var onLine: [Segment] = []
            while index < segments.count, segments[index].line == line {
                onLine.append(segments[index])
                index += 1
            }
            let starts = onLine.filter { !$0.isGap && $0.hasCount && $0.isRegionEntry }
            let startsSkipped = onLine.contains { !$0.hasCount && $0.isRegionEntry }
            if !startsSkipped, wrapped?.hasCount == true || !starts.isEmpty {
                result[line] = starts.reduce(wrapped?.count ?? 0) { max($0, $1.count) }
            }
            if let lastOnLine = onLine.last { wrapped = lastOnLine }
        }
        return result
    }
}

// MARK: - Decoding

extension CoverageMapping {
    /// What a function refers to its file names by: the low 64 bits of the MD5 of their encoded
    /// form, little endian.
    static func reference(of blob: Data) -> UInt64 {
        let digest = Array(Insecure.MD5.hash(data: blob))
        return digest.prefix(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
    }

    /// `[uleb count][uleb uncompressed size][uleb compressed size][names]`, the names
    /// zlib-compressed when the compressed size is not zero, each `[uleb length][bytes]`. From
    /// version 6 (encoded as 5) the first is the compilation directory the others are relative to.
    static func filenames(_ blob: Data, version: UInt32) -> [String]? {
        var reader = ByteReader(blob)
        guard let count = reader.uleb128(), let uncompressed = reader.uleb128(), let compressed = reader.uleb128()
        else { return nil }
        let encoded: Data? = compressed > 0
            ? reader.bytes(Int(compressed)).flatMap { CoverageObserverOutput.inflate($0) }
            : reader.bytes(Int(uncompressed))
        guard let encoded else { return nil }
        var names: [String] = []
        var nameReader = ByteReader(encoded)
        for _ in 0 ..< count {
            guard let length = nameReader.uleb128(), let bytes = nameReader.bytes(Int(length)) else { return nil }
            names.append(String(decoding: bytes, as: UTF8.self))
        }
        guard version >= 5, let directory = names.first else { return names }
        return [directory] + names.dropFirst().map { name in
            name.hasPrefix("/") ? name : URL(fileURLWithPath: directory).appendingPathComponent(name).standardized.path
        }
    }

    /// `[file ids][expressions][regions per file id]`, every number uleb128. A region is its
    /// counter, then its start line as a delta from the previous region's, its start column, how
    /// many lines it spans and its end column, whose high bit marks a gap region.
    static func function(_ data: Data, reference: UInt64, hash: UInt64, table: [Int]) -> Function? {
        var reader = ByteReader(data)
        guard let fileCount = reader.uleb128() else { return nil }
        var fileIDs: [Int] = []
        for _ in 0 ..< fileCount {
            guard let id = reader.uleb128(), Int(id) < table.count else { return nil }
            fileIDs.append(table[Int(id)])
        }
        guard let expressionCount = reader.uleb128() else { return nil }
        var expressions: [(Counter, Counter)] = []
        for _ in 0 ..< expressionCount {
            guard let left = reader.uleb128(), let right = reader.uleb128() else { return nil }
            expressions.append((Counter(encoded: left), Counter(encoded: right)))
        }
        var regions: [(file: Int, region: Region)] = []
        for file in fileIDs {
            guard let regionCount = reader.uleb128() else { return nil }
            var line = 0
            for _ in 0 ..< regionCount {
                guard let encoded = reader.uleb128() else { return nil }
                var kind = RegionKind.code
                var counter = Counter(encoded: encoded)
                if encoded & 3 == 0, encoded >> 2 != 0 {
                    counter = .zero
                    let tag = encoded >> 2
                    if tag & 1 == 1 {
                        kind = .expansion
                    } else {
                        switch tag >> 1 {
                        case 0: kind = .code
                        case 2: kind = .skipped
                        case 4:
                            kind = .branch
                            guard reader.uleb128() != nil, reader.uleb128() != nil else { return nil }
                        default:
                            // A region kind this reader does not know (MC/DC) carries operands of
                            // its own, so nothing after it can be trusted.
                            return nil
                        }
                    }
                }
                guard let lineDelta = reader.uleb128(), let columnStart = reader.uleb128(),
                      let lineCount = reader.uleb128(), var columnEnd = reader.uleb128()
                else { return nil }
                line += Int(lineDelta)
                if columnEnd & (1 << 31) != 0 {
                    columnEnd &= ~(1 << 31)
                    kind = .gap
                }
                regions.append((file, Region(
                    kind: kind, counter: counter, lineStart: line, columnStart: Int(columnStart),
                    lineEnd: line + Int(lineCount), columnEnd: Int(columnEnd)
                )))
            }
        }
        return Function(reference: reference, hash: hash, expressions: expressions, regions: regions)
    }
}

// MARK: - Mach-O

extension CoverageMapping {
    /// The arm64 slice of a universal file, else its first 64-bit one, as a range of `data`; nil
    /// when `data` is not universal or holds no such slice. The fat header and its entries are
    /// big-endian, whatever the host.
    static func universalSlice(of data: Data) -> Range<Int>? {
        guard let header: fat_header = data.structure(at: 0) else { return nil }
        let magic = UInt32(bigEndian: header.magic)
        guard magic == FAT_MAGIC || magic == FAT_MAGIC_64 else { return nil }
        let wide = magic == FAT_MAGIC_64
        let stride = wide ? MemoryLayout<fat_arch_64>.size : MemoryLayout<fat_arch>.size
        var chosen: Range<Int>?
        for index in 0 ..< Int(UInt32(bigEndian: header.nfat_arch)) {
            let entry = MemoryLayout<fat_header>.size + index * stride
            let cpu: cpu_type_t
            let candidate: Range<Int>?
            if wide {
                guard let arch: fat_arch_64 = data.structure(at: entry) else { break }
                cpu = cpu_type_t(bigEndian: arch.cputype)
                candidate = data.range(offset: UInt64(bigEndian: arch.offset), size: UInt64(bigEndian: arch.size))
            } else {
                guard let arch: fat_arch = data.structure(at: entry) else { break }
                cpu = cpu_type_t(bigEndian: arch.cputype)
                candidate = data.range(offset: UInt64(UInt32(bigEndian: arch.offset)), size: UInt64(UInt32(bigEndian: arch.size)))
            }
            // A slice that runs past the file, or whose size does not fit, is malformed and skipped.
            guard let slice = candidate else { continue }
            if cpu == CPU_TYPE_ARM64 { return slice }
            if chosen == nil, cpu & CPU_ARCH_ABI64 != 0 { chosen = slice }
        }
        return chosen
    }

    /// The named sections of a 64-bit Mach-O image, or of its chosen slice when it is universal.
    /// The image's own fields are read as laid out, which is host order on every Apple platform.
    static func sections(of image: Data, named names: Set<String>) -> [String: Data] {
        var result: [String: Data] = [:]
        forEachLoadCommand(in: image) { base, command, load in
            guard load.cmd == UInt32(LC_SEGMENT_64), let segment: segment_command_64 = image.structure(at: command)
            else { return true }
            for index in 0 ..< Int(segment.nsects) {
                let offset = command + MemoryLayout<segment_command_64>.size + index * MemoryLayout<section_64>.size
                guard let section: section_64 = image.structure(at: offset) else { break }
                let name = withUnsafeBytes(of: section.sectname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                guard names.contains(name),
                      let range = image.range(offset: UInt64(base) + UInt64(section.offset), size: section.size)
                else { continue }
                result[name] = image.subdata(in: image.startIndex + range.lowerBound ..< image.startIndex + range.upperBound)
            }
            return true
        }
        return result
    }

    /// Whether the symbol table of a 64-bit Mach-O image, or of its chosen slice, holds a symbol
    /// named exactly `name`, defined or not.
    static func namesSymbol(_ name: String, in image: Data) -> Bool {
        let target = Array(name.utf8)
        var found = false
        forEachLoadCommand(in: image) { base, command, load in
            guard load.cmd == UInt32(LC_SYMTAB), let symtab: symtab_command = image.structure(at: command)
            else { return true }
            let entrySize = MemoryLayout<nlist_64>.size
            guard let entries = image.range(
                offset: UInt64(base) + UInt64(symtab.symoff),
                size: UInt64(symtab.nsyms) * UInt64(entrySize)
            ),
                let strings = image.range(offset: UInt64(base) + UInt64(symtab.stroff), size: UInt64(symtab.strsize))
            else { return false }
            for index in 0 ..< Int(symtab.nsyms) {
                guard let entry: nlist_64 = image.structure(at: entries.lowerBound + index * entrySize) else { break }
                let start = strings.lowerBound + Int(entry.n_un.n_strx)
                guard start + target.count < strings.upperBound,
                      image[image.startIndex + start + target.count] == 0,
                      image[image.startIndex + start ..< image.startIndex + start + target.count].elementsEqual(target)
                else { continue }
                found = true
                break
            }
            return false
        }
        return found
    }

    /// Walks the load commands of a 64-bit Mach-O image, or of its chosen slice, handing each the
    /// slice's offset, the command's own offset and its header, until `body` returns false or a
    /// command runs past the image.
    private static func forEachLoadCommand(in image: Data, _ body: (Int, Int, load_command) -> Bool) {
        let base = universalSlice(of: image)?.lowerBound ?? 0
        guard let header: mach_header_64 = image.structure(at: base), header.magic == MH_MAGIC_64 else { return }
        var command = base + MemoryLayout<mach_header_64>.size
        for _ in 0 ..< Int(header.ncmds) {
            guard let load: load_command = image.structure(at: command), load.cmdsize > 0,
                  command + Int(load.cmdsize) <= image.count,
                  body(base, command, load)
            else { return }
            command += Int(load.cmdsize)
        }
    }
}

extension Data {
    /// `offset ..< offset + size` as a range of this data, checked in the unsigned domain before any
    /// conversion: nil when the span runs past the end or either value does not fit, so a malformed
    /// header is skipped rather than trapping on the conversion.
    func range(offset: UInt64, size: UInt64) -> Range<Int>? {
        let count = UInt64(count)
        guard offset <= count, size <= count - offset else { return nil }
        return Int(offset) ..< Int(offset + size)
    }

    /// The C structure laid out at `offset`, byte for byte; nil when it would run past the end.
    func structure<T>(at offset: Int) -> T? {
        let start = startIndex + offset
        guard offset >= 0, start + MemoryLayout<T>.size <= endIndex else { return nil }
        return self[start ..< start + MemoryLayout<T>.size].withUnsafeBytes { $0.loadUnaligned(as: T.self) }
    }
}

/// A decoded mapping with the files it is trusted for: those whose executable lines and covered
/// lines, computed here from the run's profile, are exactly what `llvm-cov` reports. A file that
/// differs (a mapping feature this reader gets wrong, a newer format) yields no line evidence,
/// and its tests keep file-level evidence.
struct VerifiedCoverageMapping {
    let mapping: CoverageMapping
    private(set) var verifiedFiles: Set<Int> = []
    let fileIndex: [String: Int]

    init(mapping: CoverageMapping, verifiedFiles: Set<Int>) {
        self.mapping = mapping
        self.verifiedFiles = verifiedFiles
        fileIndex = Dictionary(mapping.files.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init(
        mapping: CoverageMapping,
        report: TestCoverageEvidenceService.LCOVFunctionTable,
        profileCounts: [CoverageMapping.FunctionKey: [UInt64]]
    ) {
        self.init(mapping: mapping, verifiedFiles: [])
        guard !profileCounts.isEmpty else { return }
        var counts: [Int: [UInt64]] = [:]
        for (key, values) in profileCounts {
            if let index = mapping.functionIndex[key] { counts[index] = values }
        }
        for (path, executable) in report.executableLines {
            guard let file = fileIndex[path] else { continue }
            let lines = mapping.lines(file: file, counts: counts)
            guard IndexSet(lines.keys) == executable,
                  IndexSet(lines.filter { $0.value > 0 }.keys) == report.coveredLines[path] ?? IndexSet()
            else { continue }
            verifiedFiles.insert(file)
        }
    }
}

extension IndexSet {
    fileprivate init(_ integers: some Sequence<Int>) {
        self.init()
        for integer in integers {
            insert(integer)
        }
    }
}

extension CoverageObserverOutput {
    /// The lines a record ran, per file, for the files its images' mappings are trusted for.
    func lines(of record: Record, mappings: [String: VerifiedCoverageMapping]) -> [String: IndexSet] {
        var result: [String: IndexSet] = [:]
        for (imageIndex, counters) in record.counters {
            guard let image = images[imageIndex], let verified = mappings[image.path],
                  let deltas = record.deltas[imageIndex], deltas.count == counters.count
            else { continue }
            let mapping = verified.mapping
            var counts: [Int: [UInt64]] = [:]
            var files: Set<Int> = []
            for (counter, delta) in zip(counters, deltas) {
                guard let owner = image.function(owning: Int(counter)),
                      let function = mapping.functionIndex[.init(reference: owner.reference, hash: owner.hash)]
                else { continue }
                if counts[function] == nil {
                    counts[function] = Array(repeating: 0, count: owner.count)
                    files.formUnion(mapping.functions[function].regions.map(\.file))
                }
                counts[function]?[Int(counter) - owner.first] = delta
            }
            for file in files where verified.verifiedFiles.contains(file) {
                let covered = mapping.lines(file: file, counts: counts).filter { $0.value > 0 }.keys
                guard !covered.isEmpty else { continue }
                result[mapping.files[file], default: IndexSet()].formUnion(IndexSet(covered))
            }
        }
        return result
    }
}

extension CoverageObserverOutput.Image {
    /// The function a counter belongs to: `functions` is ascending by first counter.
    func function(owning counter: Int) -> CoverageObserverOutput.FunctionCounters? {
        var low = 0
        var high = functions.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let candidate = functions[middle]
            if counter < candidate.first {
                high = middle - 1
            } else if counter >= candidate.first + candidate.count {
                low = middle + 1
            } else {
                return candidate
            }
        }
        return nil
    }
}
