import Foundation

/// Takes the checkout's machine-specific roots out of cache keys and stored text, as Bazel's `rules_rust` and blaze do,
/// so another checkout path or machine finds the same entries. Compiled outputs are made path-free separately, by
/// `--remap-path-prefix`; dep-info files and rustc's artifact notifications must name real paths, so they are stored
/// with placeholders and given this machine's roots back when restored.
struct CargoRelocation: Equatable {
    struct Root: Equatable {
        let path: String
        let placeholder: String
        let remapped: String
    }

    /// Most specific first, so a target directory inside the workspace is matched before the workspace.
    let roots: [Root]

    init(environment: [String: String], sysroot: URL) {
        let home = environment["CARGO_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cargo").path
        var roots = [
            Root(path: sysroot.path, placeholder: "@@TUIST_SYSROOT@@", remapped: "/tuist/sysroot"),
            Root(
                path: URL(fileURLWithPath: home).standardizedFileURL.path,
                placeholder: "@@TUIST_CARGO_HOME@@",
                remapped: "/tuist/cargo"
            ),
        ]
        if let target = environment["TUIST_CARGO_TARGET_DIR"] {
            roots.append(Root(
                path: URL(fileURLWithPath: target).standardizedFileURL.path, placeholder: "@@TUIST_TARGET@@",
                remapped: "/tuist/target"
            ))
        }
        if let workspace = environment["TUIST_CARGO_WORKSPACE_ROOT"] {
            roots.append(Root(
                path: URL(fileURLWithPath: workspace).standardizedFileURL.path, placeholder: "@@TUIST_WORKSPACE@@", remapped: ""
            ))
        }
        roots = roots.filter { $0.path.count > 1 && $0.path.hasPrefix("/") }
        // macOS's `/var`, `/tmp` and `/etc` are links into `/private`; tools name a checkout under `$TMPDIR` either way.
        roots += roots.filter { Self.canonical("/private" + $0.path) == $0.path }
            .map { Root(path: "/private" + $0.path, placeholder: $0.placeholder, remapped: $0.remapped) }
        self.roots = roots.sorted { $0.path.count > $1.path.count }
    }

    /// A lexically standardized path that spells macOS's `/private` links like `standardizedFileURL` does for
    /// existing paths, but also for paths that no longer exist, such as a compiler's deleted scratch files.
    static func canonical(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardized.path
        for link in ["/var", "/tmp", "/etc"]
            where standardized == "/private" + link || standardized.hasPrefix("/private" + link + "/")
        {
            return String(standardized.dropFirst("/private".count))
        }
        return standardized
    }

    /// rustc applies the last matching mapping, so the broadest root comes first. The workspace maps to relative
    /// paths, matching what Cargo already passes for its members.
    var remapArguments: [String] {
        roots.reversed().map { "--remap-path-prefix=\($0.path)\($0.remapped.isEmpty ? "/" : "")=\($0.remapped)" }
    }

    /// Replaces each root that appears as a whole path prefix: `/a/proj` matches `/a/proj` and `/a/proj/x`, never
    /// `/a/project`.
    func relative(_ text: String) -> String {
        guard text.contains("/") else { return text }
        var result = text
        for root in roots {
            var output = ""
            var rest = Substring(result)
            while let range = rest.range(of: root.path) {
                let next = range.upperBound == rest.endIndex ? nil : rest[range.upperBound]
                output += rest[..<range.lowerBound]
                if next == nil || next == "/" || !(next!.isLetter || next!.isNumber || "._-".contains(next!)) {
                    output += root.placeholder
                } else {
                    output += rest[range]
                }
                rest = rest[range.upperBound...]
            }
            result = output + rest
        }
        return result
    }

    /// Restores this machine's roots, or `nil` when the text names a root this machine does not have.
    func absolute(_ text: String) -> String? {
        var result = text
        for root in roots {
            result = result.replacingOccurrences(of: root.placeholder, with: root.path)
        }
        return result.contains("@@TUIST_") ? nil : result
    }

    /// Roots whose absolute paths an output names in what it does, such as a string from `env!("CARGO_MANIFEST_DIR")`:
    /// such an output only behaves the same at that path. A Mach-O image's link-edit segment is skipped, since its
    /// debug map names object files by absolute path without affecting behavior.
    func boundRoots(in data: Data) -> [Root] {
        let scanned = Self.behavioralBytes(data)
        return roots.filter { scanned.range(of: Data($0.path.utf8)) != nil }
    }

    static func behavioralBytes(_ data: Data) -> Data {
        guard data.count > 32, data.prefix(4) == Data([0xCF, 0xFA, 0xED, 0xFE]) else { return data }
        func integer<T: FixedWidthInteger>(_ offset: Int, _: T.Type) -> T? {
            guard offset + MemoryLayout<T>.size <= data.count else { return nil }
            return data[data.startIndex + offset ..< data.startIndex + offset + MemoryLayout<T>.size]
                .enumerated().reduce(T(0)) { $0 | T($1.element) << (8 * $1.offset) }
        }
        guard let count = integer(16, UInt32.self) else { return data }
        var scanned = Data(data)
        var linkEdit: Int?
        var offset = 32
        for _ in 0 ..< min(count, 4096) {
            guard let command = integer(offset, UInt32.self), let size = integer(offset + 4, UInt32.self), size >= 8,
                  offset + Int(size) <= data.count
            else { return data }
            // A dylib's own install name (LC_ID_DYLIB) names where it was linked. rustc loads proc macros by explicit
            // path, so the name never changes behavior.
            if command == 0xD {
                scanned.replaceSubrange(offset + 8 ..< offset + Int(size), with: Data(count: Int(size) - 8))
            }
            if command == 0x19, offset + 48 <= data.count,
               data[data.startIndex + offset + 8 ..< data.startIndex + offset + 24].prefix(while: { $0 != 0 })
               .elementsEqual("__LINKEDIT".utf8),
               let fileOffset = integer(offset + 40, UInt64.self), fileOffset <= UInt64(data.count)
            {
                linkEdit = Int(fileOffset)
            }
            offset += Int(size)
        }
        return linkEdit.map { scanned.prefix($0) } ?? scanned
    }

    func relative(_ data: Data) -> Data? {
        String(data: data, encoding: .utf8).map { Data(relative($0).utf8) }
    }

    func absolute(_ data: Data) -> Data? {
        String(data: data, encoding: .utf8).flatMap(absolute).map { Data($0.utf8) }
    }
}
