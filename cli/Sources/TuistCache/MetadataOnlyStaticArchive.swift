import Foundation

/// Proves every member and architecture contains only compiler metadata and Xcode's version constants.
/// Symbol/size tools can silently skip unknown archive members, including LLVM bitcode.
enum MetadataOnlyStaticArchive {
    private struct Section {
        let name: String
        let segment: String
        let address: Int
        let size: Int
        let offset: Int
    }

    static func verify(_ data: Data, moduleName: String, depth: Int = 0) -> Bool {
        guard depth <= 2 else { return false }
        if data.starts(with: Data("!<arch>\n".utf8)) {
            return verifyArchive(data, moduleName: moduleName, depth: depth)
        }
        let magic = integer(data, at: 0, bigEndian: true)
        if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF {
            return verifyFatBinary(data, moduleName: moduleName, wide: magic == 0xCAFE_BABF, depth: depth)
        }
        return verifyObject(data, moduleName: moduleName)
    }

    private static func verifyArchive(_ data: Data, moduleName: String, depth: Int) -> Bool {
        var offset = 8
        var objects = 0
        while offset < data.count {
            guard data.count - offset >= 60,
                  data.subdata(in: offset + 58 ..< offset + 60) == Data("`\n".utf8),
                  let sizeText = String(bytes: data[offset + 48 ..< offset + 58], encoding: .ascii),
                  let size = Int(sizeText.trimmingCharacters(in: .whitespaces)),
                  size >= 0, size <= data.count - offset - 60,
                  let nameText = String(bytes: data[offset ..< offset + 16], encoding: .ascii)
            else { return false }
            let end = offset + 60 + size
            var start = offset + 60
            var name = nameText.trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("#1/") {
                guard let length = Int(name.dropFirst(3)), length >= 0, length <= size,
                      let extended = String(bytes: data[start ..< start + length], encoding: .utf8) else { return false }
                name = extended.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
                start += length
            }
            let indexes = ["/", "//", "__.SYMDEF", "__.SYMDEF SORTED", "__.SYMDEF_64", "__.SYMDEF_64 SORTED"]
            if !indexes.contains(name) {
                guard verify(data.subdata(in: start ..< end), moduleName: moduleName, depth: depth + 1) else { return false }
                objects += 1
            }
            offset = end + (end % 2)
        }
        return offset == data.count && objects > 0
    }

    private static func verifyFatBinary(_ data: Data, moduleName: String, wide: Bool, depth: Int) -> Bool {
        let stride = wide ? 32 : 20
        guard let count = integer(data, at: 4, bigEndian: true), count > 0,
              count <= (data.count - 8) / stride else { return false }
        for index in 0 ..< count {
            let entry = 8 + index * stride
            guard let offset = integer(data, at: entry + 8, bytes: wide ? 8 : 4, bigEndian: true),
                  let size = integer(data, at: entry + (wide ? 16 : 12), bytes: wide ? 8 : 4, bigEndian: true),
                  offset >= 8 + count * stride, offset <= data.count, size <= data.count - offset,
                  verify(data.subdata(in: offset ..< offset + size), moduleName: moduleName, depth: depth + 1)
            else { return false }
        }
        return true
    }

    private static func verifyObject(_ data: Data, moduleName: String) -> Bool {
        // Only 64-bit little-endian MH_OBJECT files qualify, never a stripped linked image.
        guard integer(data, at: 0) == 0xFEED_FACF, integer(data, at: 12) == 1,
              let commands = integer(data, at: 16), let commandBytes = integer(data, at: 20),
              data.count >= 32, commandBytes <= data.count - 32, commands <= commandBytes / 8
        else { return false }
        let end = 32 + commandBytes
        var offset = 32
        var sections: [Section] = []
        var symbolTable: Int?
        var segments = 0
        for _ in 0 ..< commands {
            guard let command = integer(data, at: offset), let size = integer(data, at: offset + 4),
                  size >= 8, size <= end - offset else { return false }
            if command == 0x19 { // LC_SEGMENT_64
                guard size >= 72, integer(data, at: offset + 24, bytes: 8) == 0,
                      let vmSize = integer(data, at: offset + 32, bytes: 8),
                      let fileOffset = integer(data, at: offset + 40, bytes: 8), fileOffset <= data.count,
                      let fileSize = integer(data, at: offset + 48, bytes: 8), fileSize <= data.count - fileOffset,
                      let count = integer(data, at: offset + 64), count <= (size - 72) / 80
                else { return false }
                var vmEnd = 0
                var fileEnd = fileOffset
                for index in 0 ..< count {
                    let section = offset + 72 + index * 80
                    guard let name = String(bytes: data[section ..< section + 16].prefix { $0 != 0 }, encoding: .utf8),
                          let segment = String(bytes: data[section + 16 ..< section + 32].prefix { $0 != 0 }, encoding: .utf8),
                          let address = integer(data, at: section + 32, bytes: 8), address <= vmSize,
                          let length = integer(data, at: section + 40, bytes: 8), length <= vmSize - address,
                          let contents = integer(data, at: section + 48), contents >= fileOffset,
                          contents <= fileOffset + fileSize, length <= fileOffset + fileSize - contents,
                          let flags = integer(data, at: section + 64),
                          let relocations = integer(data, at: section + 60)
                    else { return false }
                    if segment == "__DWARF", flags == 0x0200_0000 {
                        // DWARF indexes and compile units are not executable or allocated product storage.
                    } else {
                        guard relocations == 0 else { return false }
                        if length > 0 {
                            if segment == "__DATA", name == "__objc_imageinfo", flags == 0x1000_0000 {
                                guard length == 8, integer(data, at: contents) == 0,
                                      let imageFlags = integer(data, at: contents + 4),
                                      // Only the simulated-image and category-class-properties bits qualify.
                                      [0, 0x20, 0x40, 0x60].contains(imageFlags) else { return false }
                            } else {
                                guard segment == "__TEXT", name == "__const", flags == 0 else { return false }
                            }
                        }
                    }
                    sections.append(Section(name: name, segment: segment, address: address, size: length, offset: contents))
                    vmEnd = max(vmEnd, address + length)
                    fileEnd = max(fileEnd, contents + length)
                }
                guard vmSize == vmEnd, fileSize == fileEnd - fileOffset else { return false }
                segments += 1
            } else if command == 0x2 { // LC_SYMTAB
                guard size >= 24, symbolTable == nil else { return false }
                symbolTable = offset
            }
            offset += size
        }
        guard offset == end, segments == 1 else { return false }
        let constants = sections.indices.filter { sections[$0].segment == "__TEXT" && sections[$0].name == "__const"
            && sections[$0].size > 0
        }
        guard constants.count <= 1 else { return false }
        var versionOffsets: [String: Int] = [:]
        if let table = symbolTable {
            guard let symbols = integer(data, at: table + 8), symbols <= data.count,
                  let count = integer(data, at: table + 12), count <= (data.count - symbols) / 16,
                  let strings = integer(data, at: table + 16), strings <= data.count,
                  let stringSize = integer(data, at: table + 20), stringSize <= data.count - strings
            else { return false }
            for index in 0 ..< count {
                let symbol = symbols + index * 16
                guard let nameOffset = integer(data, at: symbol), nameOffset < stringSize,
                      let name = string(data, at: strings + nameOffset, limit: strings + stringSize),
                      let type = integer(data, at: symbol + 4, bytes: 1),
                      let section = integer(data, at: symbol + 5, bytes: 1),
                      let value = integer(data, at: symbol + 8, bytes: 8)
                else { return false }
                if type == 0 || type == 1 { // Undefined/common: nonzero values allocate storage at link time.
                    guard value == 0 else { return false }
                } else {
                    guard section > 0, section <= sections.count else { return false }
                    let contents = sections[section - 1]
                    if type == 0x0E, name.hasPrefix("ltmp"), !name.dropFirst(4).isEmpty,
                       name.dropFirst(4).allSatisfy(\.isNumber), value == contents.address
                    {
                        continue
                    }
                    guard type == 0x0F, constants.first == section - 1,
                          ["_\(moduleName)VersionString", "_\(moduleName)VersionNumber"].contains(name),
                          versionOffsets[name] == nil, value >= contents.address,
                          value - contents.address < contents.size else { return false }
                    versionOffsets[name] = value - contents.address
                }
            }
        }
        guard let constant = constants.first else { return versionOffsets.isEmpty }
        let contents = sections[constant]
        guard versionOffsets.count == 2, versionOffsets["_\(moduleName)VersionString"] == 0,
              let number = versionOffsets["_\(moduleName)VersionNumber"], contents.size >= 8,
              number == contents.size - 8,
              let versionString = string(data, at: contents.offset, limit: contents.offset + number),
              versionString.hasPrefix("@(#)PROGRAM:\(moduleName)  PROJECT:"), versionString.hasSuffix("\n"),
              let separator = versionString.lastIndex(of: "-"),
              let version = Double(versionString[versionString.index(after: separator)...].dropLast()),
              version.isFinite, version >= 0,
              let stored = integer(data, at: contents.offset + number, bytes: 8), UInt64(stored) == version.bitPattern
        else { return false }
        let padding = versionString.utf8.count + 1
        return number >= padding && number - padding < 8
            && data[contents.offset + padding ..< contents.offset + number].allSatisfy { $0 == 0 }
    }

    private static func string(_ data: Data, at offset: Int, limit: Int) -> String? {
        guard offset >= 0, offset < limit, limit <= data.count,
              let end = data[offset ..< limit].firstIndex(of: 0) else { return nil }
        return String(bytes: data[offset ..< end], encoding: .utf8)
    }

    private static func integer(_ data: Data, at offset: Int, bytes: Int = 4, bigEndian: Bool = false) -> Int? {
        guard offset >= 0, offset <= data.count, bytes <= data.count - offset else { return nil }
        var value: UInt64 = 0
        for index in 0 ..< bytes {
            value |= UInt64(data[offset + index]) << (8 * (bigEndian ? bytes - index - 1 : index))
        }
        return Int(exactly: value)
    }
}
