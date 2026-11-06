import Foundation

/// Proves that every member and architecture contains only empty Mach-O object sections.
/// Symbol/size tools can silently skip unknown archive members, including LLVM bitcode.
enum EmptyStaticArchive {
    static func isEmpty(_ data: Data, depth: Int = 0) -> Bool {
        guard depth <= 2 else { return false }
        if data.starts(with: Data("!<arch>\n".utf8)) {
            return isEmptyArchive(data, depth: depth)
        }
        let magic = integer(data, at: 0, bigEndian: true)
        if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF {
            return isEmptyFatBinary(data, wide: magic == 0xCAFE_BABF, depth: depth)
        }
        return isEmptyObject(data)
    }

    private static func isEmptyArchive(_ data: Data, depth: Int) -> Bool {
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
                guard isEmpty(data.subdata(in: start ..< end), depth: depth + 1) else { return false }
                objects += 1
            }
            offset = end + (end % 2)
        }
        return offset == data.count && objects > 0
    }

    private static func isEmptyFatBinary(_ data: Data, wide: Bool, depth: Int) -> Bool {
        let stride = wide ? 32 : 20
        guard let count = integer(data, at: 4, bigEndian: true), count > 0,
              count <= (data.count - 8) / stride else { return false }
        for index in 0 ..< count {
            let entry = 8 + index * stride
            guard let offset = integer(data, at: entry + 8, bytes: wide ? 8 : 4, bigEndian: true),
                  let size = integer(data, at: entry + (wide ? 16 : 12), bytes: wide ? 8 : 4, bigEndian: true),
                  offset >= 8 + count * stride, offset <= data.count, size <= data.count - offset,
                  isEmpty(data.subdata(in: offset ..< offset + size), depth: depth + 1)
            else { return false }
        }
        return true
    }

    private static func isEmptyObject(_ data: Data) -> Bool {
        // Only 64-bit little-endian MH_OBJECT files qualify, never a stripped linked image.
        guard integer(data, at: 0) == 0xFEED_FACF, integer(data, at: 12) == 1,
              let commands = integer(data, at: 16), let commandBytes = integer(data, at: 20),
              data.count >= 32, commandBytes <= data.count - 32, commands <= commandBytes / 8
        else { return false }
        let end = 32 + commandBytes
        var offset = 32
        var segments = 0
        for _ in 0 ..< commands {
            guard let command = integer(data, at: offset), let size = integer(data, at: offset + 4),
                  size >= 8, size <= end - offset else { return false }
            if command == 0x19 { // LC_SEGMENT_64
                guard size >= 72, integer(data, at: offset + 32, bytes: 8) == 0,
                      integer(data, at: offset + 48, bytes: 8) == 0,
                      let sections = integer(data, at: offset + 64), sections <= (size - 72) / 80
                else { return false }
                for section in 0 ..< sections {
                    guard integer(data, at: offset + 72 + section * 80 + 40, bytes: 8) == 0 else { return false }
                }
                segments += 1
            } else if command == 0x2 { // LC_SYMTAB
                guard size >= 24, let symbols = integer(data, at: offset + 8), symbols <= data.count,
                      let count = integer(data, at: offset + 12), count <= (data.count - symbols) / 16
                else { return false }
                // Common symbols allocate zero-initialized storage at link time without a section.
                for symbol in 0 ..< count {
                    guard integer(data, at: symbols + symbol * 16 + 8, bytes: 8) == 0 else { return false }
                }
            }
            offset += size
        }
        return offset == end && segments > 0
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
