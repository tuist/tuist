import Foundation

/// Turns `git` output into the history types: `git log` lines into commits, and `git ls-tree`
/// entries into a commit's files.
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

    /// The parents of each commit in a `git log --format=raw` listing, as their commit objects
    /// store them. Headers start at the line's first column; the message and multi-line header
    /// values are indented.
    static func parseRawParents(_ output: String) -> [String: [String]] {
        var parents: [String: [String]] = [:]
        var current: String?
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("commit ") {
                let sha = String(line.dropFirst("commit ".count).prefix { $0 != " " })
                current = sha
                parents[sha] = []
            } else if line.hasPrefix("parent "), let current {
                parents[current]?.append(String(line.dropFirst("parent ".count)))
            }
        }
        return parents
    }

    /// The entries of `git ls-tree -r -z`: `<mode> <type> <object>\t<path>`, NUL-separated. Only
    /// blobs count: a submodule's entry is a commit.
    static func parseCommitFiles(_ output: String) -> [GitCommitFile] {
        output.split(separator: "\0", omittingEmptySubsequences: true).compactMap { entry in
            guard let tab = entry.firstIndex(of: "\t") else { return nil }
            let fields = entry[..<tab].split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 3, fields[1] == "blob", let mode = Int(fields[0], radix: 8) else { return nil }
            return GitCommitFile(path: String(entry[entry.index(after: tab)...]), blobId: String(fields[2]), mode: mode)
        }
    }
}
