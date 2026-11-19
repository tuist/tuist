import Foundation
import Path

/// The manifests a sync compares, and what the sandbox's probe reports.
extension SandboxSync {
    /// What the sandbox's copy holds: its absolute path, the worktree it was last synced from, and the commit a
    /// repository snapshot checked out there, which no sync sent.
    struct Probe: Equatable {
        let root: String
        let id: String?
        let commit: String?
    }

    /// The repository's name in a remote URL, such as `app` in `https://github.com/acme/app.git` or `git@github.com:acme/app`:
    /// its last path component without `.git`. A repository snapshot clones there, so every checkout of the repository
    /// syncs to the same path in the sandbox whatever its local directory is called, and Xcode's DerivedData, which is
    /// keyed by the workspace's path, carries over. Nil when the URL names nothing usable as a directory.
    static func repositoryName(fromRemoteURL url: String) -> String? {
        var name = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasSuffix("/") {
            name.removeLast()
        }
        name = String(name.split(whereSeparator: { $0 == "/" || $0 == ":" }).last ?? "")
        if name.hasSuffix(".git") { name.removeLast(4) }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !name.isEmpty, name != ".", name != "..", name.allSatisfy(allowed.contains) else { return nil }
        return name
    }

    /// Parses the probe's `root <path>` and `id <id>` lines, and the optional `commit <sha>` line of a copy a repository
    /// snapshot prepared.
    static func probe(_ stdout: String) -> Probe? {
        let lines = stdout.split(separator: "\n").map(String.init)
        guard let root = lines.first(where: { $0.hasPrefix("root ") })?.dropFirst(5),
              let id = lines.first(where: { $0.hasPrefix("id ") || $0 == "id" })
        else { return nil }
        func value(_ line: String?, _ prefix: Int) -> String? {
            let value = line.map { $0.dropFirst(prefix).trimmingCharacters(in: .whitespaces) } ?? ""
            return value.isEmpty ? nil : value
        }
        return Probe(root: String(root), id: value(id, 3), commit: value(lines.first(where: { $0.hasPrefix("commit ") }), 7))
    }

    /// The paths that left the worktree since `previous`, and those that joined it.
    static func delta(from previous: [Entry], to entries: [Entry]) -> (deleted: [String], added: [String]) {
        let before = Set(previous.map(\.path))
        let after = Set(entries.map(\.path))
        return (previous.map(\.path).filter { !after.contains($0) }, entries.map(\.path).filter { !before.contains($0) })
    }

    /// The entries to send: every one when the sandbox's previous worktree is unknown, otherwise the new ones and those
    /// whose content or mode changed.
    static func changes(from previous: [Entry]?, to entries: [Entry]) -> [Entry] {
        guard let previous else { return entries }
        let known = Dictionary(previous.map { ($0.path, $0) }, uniquingKeysWith: { $1 })
        return entries.filter { known[$0.path] != $0 }
    }

    /// Parses `git ls-files -s -z` output (`<mode> <object> <stage>\t<path>\0`), leaving out submodules.
    static func entries(fromIndexListing listing: String) -> [Entry] {
        listing.split(separator: "\0").compactMap { record in
            guard let tab = record.firstIndex(of: "\t") else { return nil }
            let fields = record[..<tab].split(separator: " ")
            guard fields.count >= 2, fields[0] != "160000" else { return nil }
            return Entry(mode: String(fields[0]), object: String(fields[1]), path: String(record[record.index(after: tab)...]))
        }
    }

    /// The manifest saved between syncs: `<mode> <object>\t<path>\0` per entry.
    static func serialize(_ entries: [Entry]) -> Data {
        Data(entries.map { "\($0.mode) \($0.object)\t\($0.path)\0" }.joined().utf8)
    }

    static func entries(_ manifest: Data) -> [Entry] {
        entries(fromIndexListing: String(decoding: manifest, as: UTF8.self))
    }

    /// `$HOME/work/<name>`, with the name in the `origin` remote's URL, else the worktree directory's.
    func defaultDestination(of repository: AbsolutePath) async -> String {
        let origin = try? await git(["remote", "get-url", "origin"], in: repository)
        return "$HOME/work/\(origin.flatMap(Self.repositoryName(fromRemoteURL:)) ?? repository.basename)"
    }

    /// Saves the manifest of `commit` under `id` when this machine has no manifest of that id and the commit's files hash
    /// to it. A sandbox booted from a repository snapshot holds a clean checkout of `commit` that no sync sent, so the
    /// first sync then sends only the files that differ from it, leaving the others, and the modification times Xcode
    /// compares, alone. Anything that does not match, such as a commit this clone lacks, leaves the full sync.
    func recordCommitManifest(_ commit: String, id: String, manifests: AbsolutePath, repository: AbsolutePath) async {
        let manifest = manifests.appending(component: id)
        guard !FileManager.default.fileExists(atPath: manifest.pathString),
              [40, 64].contains(commit.count), commit.allSatisfy(\.isHexDigit)
        else { return }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("tuist-sandbox-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            let environment = ["GIT_INDEX_FILE": scratch.appendingPathComponent("index").path]
            _ = try await git(["read-tree", commit], in: repository, environment: environment)
            let listing = try await commandRunner.run(
                arguments: ["git", "-C", repository.pathString, "ls-files", "-s", "-z"],
                environment: ProcessInfo.processInfo.environment.merging(environment) { $1 }
            ).concatenatedString(including: [.standardOutput])
            let candidate = scratch.appendingPathComponent("manifest")
            try Self.serialize(Self.entries(fromIndexListing: listing)).write(to: candidate)
            guard try await git(["hash-object", "--no-filters", candidate.path], in: repository) == id else { return }
            try FileManager.default.moveItem(atPath: candidate.path, toPath: manifest.pathString)
        } catch {
            return
        }
    }
}
