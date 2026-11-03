#if os(macOS)
import Darwin
import Foundation

/// Pi-style text operations. Matching uses the original file, and every edit
/// succeeds or the file stays unchanged. Descriptors fence symlink escapes.
enum AtlasWorkstationFiles {
    static func perform(_ command: AtlasWorkstationCommand, root: URL) throws -> AtlasWorkstationResult {
        let args = command.arguments
        guard let path = args.path, !path.isEmpty, path.utf8.count <= 4096 else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        switch command.tool {
        case "read":
            return try read(path, offset: args.offset ?? 1, limit: args.limit ?? 2000, root: root)
        case "write":
            guard let content = args.content, content.utf8.count <= 65536, !content.contains("\0") else {
                throw CocoaError(.coderInvalidValue)
            }
            try replace(path, root: root, with: Data(content.utf8))
            return AtlasWorkstationResult(success: true, output: "Wrote \(content.utf8.count) bytes to \(path).")
        case "edit":
            return try edit(path, edits: args.edits ?? [], root: root)
        default:
            throw CocoaError(.coderInvalidValue)
        }
    }

    private static func read(_ path: String, offset: Int, limit: Int, root: URL) throws -> AtlasWorkstationResult {
        let data = try contents(path, root: root)
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
            return failure("Choose a UTF-8 text file, not binary content.")
        }
        guard (1...1_000_000).contains(offset), (1...2000).contains(limit) else {
            throw CocoaError(.coderInvalidValue)
        }
        let lines = text.components(separatedBy: "\n")
        guard offset <= lines.count else { return failure("Offset is beyond the file's \(lines.count) lines.") }
        var output = ""
        var next = offset
        for line in lines.dropFirst(offset - 1).prefix(limit) {
            let numbered = "\(next): \(line)\n"
            guard output.utf8.count + numbered.utf8.count <= 48 * 1024 - 256 else { break }
            output += numbered
            next += 1
        }
        if next <= lines.count {
            output += "[Truncated. Continue with offset=\(next); for an oversized line use bash.]"
        }
        return AtlasWorkstationResult(success: true, output: output)
    }

    private static func edit(_ path: String, edits: [AtlasWorkstationCommand.Edit],
                             root: URL) throws -> AtlasWorkstationResult {
        guard (1...16).contains(edits.count) else { throw CocoaError(.coderInvalidValue) }
        let original = try contents(path, root: root)
        guard var text = String(data: original, encoding: .utf8), !text.contains("\0") else {
            return failure("Choose a UTF-8 text file, not binary content.")
        }
        // Foundation's UTF-8 decoder consumes a leading BOM.
        let bom = original.starts(with: [0xEF, 0xBB, 0xBF])
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let crlf = text.contains("\r\n")
        var bytes = Data(text.replacingOccurrences(of: "\r\n", with: "\n").utf8)
        var replacements: [(Range<Int>, Data)] = []
        for edit in edits {
            let old = Data(edit.oldText.replacingOccurrences(of: "\r\n", with: "\n").utf8)
            let new = Data(edit.newText.replacingOccurrences(of: "\r\n", with: "\n").utf8)
            guard !old.isEmpty, old.count <= 65536, new.count <= 65536,
                  let range = bytes.range(of: old),
                  bytes.range(of: old, in: (range.lowerBound + 1)..<bytes.count) == nil else {
                return failure("Each oldText must match exactly once. " +
                               "No changes were made; read the file and correct the edits.")
            }
            guard !replacements.contains(where: { $0.0.overlaps(range) }) else {
                return failure("Edits overlap in the original file. No changes were made.")
            }
            replacements.append((range, new))
        }
        for (range, replacement) in replacements.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            bytes.replaceSubrange(range, with: replacement)
        }
        guard var changed = String(data: bytes, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        if crlf { changed = changed.replacingOccurrences(of: "\n", with: "\r\n") }
        if bom { changed = "\u{FEFF}" + changed }
        try replace(path, root: root, with: Data(changed.utf8), expected: original)
        return AtlasWorkstationResult(success: true, output: "Applied \(edits.count) edits to \(path).")
    }

    private static func contents(_ path: String, root: URL) throws -> Data {
        let target = try AtlasWorkstationExecution.resolve(path, root: root)
        let descriptor = Darwin.open(target.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size <= 4 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        try contained(descriptor, root: root)
        let data = try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            .read(upToCount: 4 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 4 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        return data
    }

    private static func replace(_ path: String, root: URL, with data: Data, expected: Data? = nil) throws {
        guard !path.hasPrefix("/"), !path.contains("\0"), !path.split(separator: "/").contains("..") else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let components = path.split(separator: "/")
        guard let last = components.last, last != ".", last != ".git" else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let name = String(last)
        let parent = try AtlasWorkstationExecution.resolve(components.dropLast().joined(separator: "/"), root: root)
        let descriptor = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { Darwin.close(descriptor) }
        try contained(descriptor, root: root)
        var metadata = stat()
        let exists = fstatat(descriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0
        guard exists ? metadata.st_mode & S_IFMT == S_IFREG : errno == ENOENT else {
            throw CocoaError(.fileWriteNoPermission)
        }
        if let expected, try contents(path, root: root) != expected { throw CocoaError(.fileWriteUnknown) }
        let temporary = ".atlas-\(UUID().uuidString)"
        let file = openat(descriptor, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { Darwin.close(file); unlinkat(descriptor, temporary, 0) }
        try FileHandle(fileDescriptor: file, closeOnDealloc: false).write(contentsOf: data)
        guard fchmod(file, exists ? metadata.st_mode & 0o777 : 0o644) == 0, fsync(file) == 0,
              renameat(descriptor, temporary, descriptor, name) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func contained(_ descriptor: Int32, root: URL) throws {
        var actual = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &actual) == 0 else { throw CocoaError(.fileReadNoPermission) }
        let path = URL(fileURLWithPath: String(cString: actual)).resolvingSymlinksInPath().path
        let root = root.resolvingSymlinksInPath().path
        guard path == root || path.hasPrefix(root + "/") else { throw CocoaError(.fileReadNoPermission) }
    }

    private static func failure(_ message: String) -> AtlasWorkstationResult {
        AtlasWorkstationResult(success: false, output: message)
    }
}
#endif
