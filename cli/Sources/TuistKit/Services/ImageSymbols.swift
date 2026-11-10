import Foundation
import MachO

/// The functions of a 64-bit Mach-O image, or of its chosen slice when it is universal, by offset
/// from the image's base: what TestCoverageAttribution's function records name. A function record
/// holds, for each function a test entered, the address SanitizerCoverage's PC table gives it less
/// the address the image loaded at, which is the image's `__TEXT` segment.
///
/// An offset belongs to the symbol at or before it: async functions are split into continuations
/// with no symbol of their own, which follow the function's. That only holds while the image keeps
/// its local symbols, so a stripped image (no local function symbols) maps nothing.
struct ImageSymbols {
    private let starts: [UInt64]
    private let names: [String]

    init(starts: [UInt64], names: [String]) {
        self.starts = starts
        self.names = names
    }

    /// The symbols of the image at `path`, or nil when it can't be read or has no local symbols.
    init?(imagePath path: String) {
        guard let image = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { return nil }
        self.init(image: image)
    }

    init?(image: Data) {
        let base = CoverageMapping.universalSlice(of: image)?.lowerBound ?? 0
        guard let header: mach_header_64 = image.structure(at: base), header.magic == MH_MAGIC_64 else { return nil }
        var textAddress: UInt64?
        var textSectionIndex: UInt8?
        var sectionCount = 0
        var symbolTable: symtab_command?
        var command = base + MemoryLayout<mach_header_64>.size
        for _ in 0 ..< Int(header.ncmds) {
            guard let load: load_command = image.structure(at: command), load.cmdsize > 0,
                  command + Int(load.cmdsize) <= image.count
            else { return nil }
            if load.cmd == UInt32(LC_SEGMENT_64), let segment: segment_command_64 = image.structure(at: command) {
                let segmentName = withUnsafeBytes(of: segment.segname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                if segmentName == "__TEXT" {
                    textAddress = segment.vmaddr
                    for index in 0 ..< Int(segment.nsects) {
                        let offset = command + MemoryLayout<segment_command_64>.size + index * MemoryLayout<section_64>.size
                        guard let section: section_64 = image.structure(at: offset) else { break }
                        let name = withUnsafeBytes(of: section.sectname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
                        }
                        if name == "__text" { textSectionIndex = UInt8(truncatingIfNeeded: sectionCount + index + 1) }
                    }
                }
                sectionCount += Int(segment.nsects)
            } else if load.cmd == UInt32(LC_SYMTAB) {
                symbolTable = image.structure(at: command)
            }
            command += Int(load.cmdsize)
        }
        guard let textAddress, let textSectionIndex, let symbolTable else { return nil }

        let entrySize = MemoryLayout<nlist_64>.size
        guard let entries = image.range(
            offset: UInt64(base) + UInt64(symbolTable.symoff),
            size: UInt64(symbolTable.nsyms) * UInt64(entrySize)
        ),
            let strings = image.range(offset: UInt64(base) + UInt64(symbolTable.stroff), size: UInt64(symbolTable.strsize))
        else { return nil }
        var symbols: [(UInt64, String)] = []
        var hasLocalSymbols = false
        for index in 0 ..< Int(symbolTable.nsyms) {
            guard let entry: nlist_64 = image.structure(at: entries.lowerBound + index * entrySize) else { break }
            // Defined in the text section, and no debugger entry.
            guard entry.n_type & UInt8(N_STAB) == 0, entry.n_type & UInt8(N_TYPE) == UInt8(N_SECT),
                  entry.n_sect == textSectionIndex, entry.n_value >= textAddress
            else { continue }
            let start = strings.lowerBound + Int(entry.n_un.n_strx)
            guard start < strings.upperBound,
                  let end = image[(image.startIndex + start) ..< (image.startIndex + strings.upperBound)].firstIndex(of: 0)
            else { continue }
            var name = String(decoding: image[(image.startIndex + start) ..< end], as: UTF8.self)
            if name.hasPrefix("_") { name.removeFirst() }
            if entry.n_type & UInt8(N_EXT) == 0 { hasLocalSymbols = true }
            symbols.append((entry.n_value - textAddress, name))
        }
        guard hasLocalSymbols else { return nil }
        symbols.sort { $0.0 < $1.0 }
        self.init(starts: symbols.map(\.0), names: symbols.map(\.1))
    }

    /// The symbol of the function at `offset` from the image's base, nil when it lies before every
    /// symbol.
    func function(atOffset offset: UInt64) -> String? {
        var low = 0
        var high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] <= offset { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? names[low - 1] : nil
    }
}
