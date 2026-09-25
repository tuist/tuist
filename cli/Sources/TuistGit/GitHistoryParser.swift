import Foundation

/// Turns `git` output into the history types: `git log` lines into commits, and a `--raw` listing
/// joined with a unified diff into changed files with hunks.
enum GitHistoryParser {
    /// `git log --format=%H %P %ct` lines: the SHA, the parent SHAs and the committer time.
    static func parseCommits(_ output: String) -> [GitHistoryCommit] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: " ").map(String.init)
            guard fields.count >= 2, let time = Double(fields[fields.count - 1]) else { return nil }
            return GitHistoryCommit(
                sha: fields[0],
                parents: Array(fields[1 ..< fields.count - 1]),
                committedAt: Date(timeIntervalSince1970: time)
            )
        }
    }

    /// The files of a `git diff --raw -z -M` listing joined with the hunks of the matching
    /// `git diff -U0`. Returns the files kept and how many were dropped past the limit.
    static func parseChangedFiles(raw: String, unified: String, limits: GitHistoryLimits) -> ([GitChangedFile], Int) {
        let hunksByPath = parseHunks(unified)
        let tokens = raw.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var files: [GitChangedFile] = []
        var index = 0
        var dropped = 0

        while index < tokens.count {
            let header = tokens[index]
            guard header.hasPrefix(":") else { index += 1; continue }
            // `:<old mode> <new mode> <old blob> <new blob> <status>` then one path, or two for
            // a rename or copy.
            let fields = header.dropFirst().split(separator: " ").map(String.init)
            guard fields.count >= 5, index + 1 < tokens.count else { break }
            let statusLetter = fields[4].first ?? "M"
            let twoPaths = statusLetter == "R" || statusLetter == "C"
            let previousPath = twoPaths ? tokens[index + 1] : nil
            let path = twoPaths ? (index + 2 < tokens.count ? tokens[index + 2] : tokens[index + 1]) : tokens[index + 1]
            index += twoPaths ? 3 : 2

            if files.count >= limits.maxChangedFiles {
                dropped += 1
                continue
            }

            let status: GitChangedFile.Status =
                switch statusLetter {
                case "A": .added
                case "D": .deleted
                case "R": .renamed
                default: .modified
                }
            let hunks = hunksByPath[path] ?? []
            let blob = fields[3]
            files.append(
                GitChangedFile(
                    path: path,
                    previousPath: previousPath,
                    status: status,
                    blobId: status == .deleted || blob.allSatisfy { $0 == "0" } ? nil : blob,
                    hunks: Array(hunks.prefix(limits.maxHunksPerFile)),
                    truncated: hunks.count > limits.maxHunksPerFile
                )
            )
        }

        return (files, dropped)
    }

    /// The head-side line ranges of each file's hunks in a unified diff: `+++ b/<path>` names the
    /// file, `@@ -a,b +c,d @@` covers lines c..c+d-1; a hunk with d = 0 only removed lines.
    ///
    /// Expects the `b/` prefix whatever the user's diff config says (`--dst-prefix=b/`). A `+++ `
    /// line only names the file right after the `--- ` line of a `diff --git` header: in a hunk it
    /// is an added line that starts with `++ `.
    static func parseHunks(_ unified: String) -> [String: [GitHunk]] {
        var hunks: [String: [GitHunk]] = [:]
        var path: String?
        var header = false
        var sawOldName = false
        for line in unified.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            if line.hasPrefix("diff --git ") {
                header = true
                sawOldName = false
                path = nil
            } else if header, line.hasPrefix("--- ") {
                sawOldName = true
            } else if header, sawOldName, line.hasPrefix("+++ ") {
                header = false
                path = headerPath(line.dropFirst(4))
            } else if line.hasPrefix("@@ "), let path,
                      let match = line.firstMatch(of: /^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/)
            {
                let start = Int(match.1) ?? 0
                let count = match.2.flatMap { Int($0) } ?? 1
                if count > 0 {
                    hunks[path, default: []].append(GitHunk(start: start, end: start + count - 1))
                }
            }
        }
        return hunks
    }

    /// The path of a `+++ ` header: Git ends the name with a tab when it has a space, and quotes it,
    /// C-style, when it has a character `core.quotePath=false` still escapes.
    private static func headerPath(_ name: Substring) -> String? {
        var name = name
        if name.hasSuffix("\t") { name = name.dropLast() }
        if name == "/dev/null" { return nil }
        let path = name.hasPrefix("\"") && name.hasSuffix("\"") && name.count >= 2
            ? unquote(name.dropFirst().dropLast())
            : String(name)
        return path.hasPrefix("b/") ? String(path.dropFirst(2)) : path
    }

    private static func unquote(_ quoted: Substring) -> String {
        let escapes: [UInt8: UInt8] = [
            UInt8(ascii: "a"): 0x07, UInt8(ascii: "b"): 0x08, UInt8(ascii: "t"): 0x09, UInt8(ascii: "n"): 0x0A,
            UInt8(ascii: "v"): 0x0B, UInt8(ascii: "f"): 0x0C, UInt8(ascii: "r"): 0x0D,
        ]
        let input = Array(quoted.utf8)
        var bytes: [UInt8] = []
        var index = 0
        while index < input.count {
            let byte = input[index]
            guard byte == UInt8(ascii: "\\"), index + 1 < input.count else {
                bytes.append(byte)
                index += 1
                continue
            }
            let next = input[index + 1]
            let octal = input[(index + 1) ..< min(index + 4, input.count)]
            if octal.count == 3, octal.allSatisfy({ (UInt8(ascii: "0") ... UInt8(ascii: "7")).contains($0) }) {
                bytes.append(octal.reduce(0) { $0 &* 8 &+ ($1 - UInt8(ascii: "0")) })
                index += 4
            } else {
                bytes.append(escapes[next] ?? next)
                index += 2
            }
        }
        return String(bytes: bytes, encoding: .utf8) ?? String(quoted)
    }

    /// The entries of `git ls-files --stage -z`: `<mode> <blob> <stage>\t<path>`, NUL-separated.
    /// Only stage 0 entries count (a path in a merge conflict has no single blob), and a
    /// submodule's entry names a commit rather than a blob.
    static func parseCommitFiles(_ output: String) -> [GitCommitFile] {
        output.split(separator: "\0", omittingEmptySubsequences: true).compactMap { entry in
            guard let tab = entry.firstIndex(of: "\t") else { return nil }
            let fields = entry[..<tab].split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 3, fields[2] == "0", fields[0] != "160000", let mode = Int(fields[0], radix: 8) else {
                return nil
            }
            return GitCommitFile(path: String(entry[entry.index(after: tab)...]), blobId: String(fields[1]), mode: mode)
        }
    }
}
