import Foundation
import TuistREAPI

/// What a recorded run was seen reading, with machine-specific roots relocated. Entries are found in two steps, as blaze
/// keeps build-script runs: a declared key names the read set of an earlier run, and that set's current contents form
/// the key of its outputs. A run that read the same inputs with the same contents is the same run.
struct CargoReadSet: Codable, Equatable {
    struct Entry: Codable, Hashable {
        /// `path` (a file read, looked up or found absent), `listing` (a directory listed), `env` (a variable read) or
        /// `environment` (the whole environment read).
        let kind: String
        let name: String
    }

    var entries: [Entry]

    static let maximumEntries = 20000

    /// Parses a recorder log. `nil` when the run cannot be cached: a child process that did not load the recorder
    /// (other than an allowed one, such as the system linker), a network connection, a write outside `allowedWrites`,
    /// an event the recorder could not represent, or too many inputs.
    static func parse(
        log: URL, relocation: CargoRelocation, excludedRoots: [String], targetDirectory: String?,
        allowedWrites: [String], allowedSpawn: (String) -> Bool = { _ in false },
        keyedEnvironment: (String) -> Bool
    ) -> CargoReadSet? {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return nil }
        var processes = 0
        var spawns = 0
        var environReads: [String: Int] = [:]
        var passedThrough: [String: Int] = [:]
        var written: Set<String> = []
        var observed: [(kind: Character, path: String)] = []
        var variables: Set<String> = []
        func within(_ path: String, _ roots: [String]) -> Bool {
            roots.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, let kind = fields[1].first, fields[1].count == 1 else { return nil }
            let pid = String(fields[0])
            let value = String(fields[2])
            switch kind {
            case "P": processes += 1
            case "X": if !allowedSpawn(value) { spawns += 1 }
            case "x": passedThrough[pid, default: 0] += 1
            case "e": environReads[pid, default: 0] += 1
            case "E": variables.insert(value)
            case "W":
                let path = standardized(value)
                guard within(path, allowedWrites) || path.hasPrefix("/dev/") else { return nil }
                written.insert(path)
            case "R", "S", "A", "D": observed.append((kind, standardized(value)))
            default: return nil
            }
        }
        // Every process started must have loaded the recorder, the first one included.
        guard processes >= 1, processes >= spawns + 1 else { return nil }
        var entries: Set<Entry> = []
        for (pid, count) in environReads where count > passedThrough[pid, default: 0] {
            entries.insert(Entry(kind: "environment", name: "*"))
        }
        for name in variables where !keyedEnvironment(name) {
            entries.insert(Entry(kind: "env", name: name))
        }
        // Writable areas inside a root (the compiler's output directory) hold only this run's scratch files. A writable
        // area outside every root (the temporary directory) can still contain a root, such as a checkout under
        // `$TMPDIR`, whose files remain inputs.
        let rootPaths = relocation.roots.map(\.path)
        let scratch = allowedWrites.filter { within($0, rootPaths) }
        for (kind, path) in observed where !written.contains(path) {
            if within(path, excludedRoots) || within(path, scratch) { continue }
            if within(path, allowedWrites), !within(path, rootPaths) { continue }
            // Looking up `/` or a directory above a root says nothing a relocated key does not already hold.
            if path == "/" || relocation.roots.contains(where: { $0.path.hasPrefix(path + "/") }) { continue }
            if let targetDirectory, within(path, [targetDirectory]) {
                // Dependency rlibs and rmetas are named by the compiler's externs, keyed by content, and are written
                // concurrently by other compilers. Proc-macro libraries found through search paths are read whole
                // and keyed here; generated sources elsewhere in the target directory are inputs like any other file.
                let components = path.dropFirst(targetDirectory.count + 1).split(separator: "/")
                let pathExtension = URL(fileURLWithPath: path).pathExtension
                if kind != "R" || components.contains(".fingerprint") || components.contains("incremental")
                    || ["rlib", "rmeta", "d"].contains(pathExtension)
                    || (components.contains("deps") && !["dylib", "so"].contains(pathExtension)) { continue }
            }
            entries.insert(Entry(kind: kind == "D" ? "listing" : "path", name: relocation.relative(path)))
        }
        guard entries.count <= maximumEntries else { return nil }
        return CargoReadSet(entries: entries.sorted { ($0.kind, $0.name) < ($1.kind, $1.name) })
    }

    /// Whether every recorded file is older than `date`: an input that changed while the run read it would key new
    /// content with old output.
    func unchanged(since date: Date, relocation: CargoRelocation) -> Bool {
        let limit = date.timeIntervalSince1970
        return entries.allSatisfy { entry in
            guard entry.kind == "path", let path = relocation.absolute(entry.name) else { return true }
            var value = stat()
            guard stat(path, &value) == 0 else { return true }
            #if os(Linux)
                let (changedTime, modifiedTime) = (value.st_ctim, value.st_mtim)
            #else
                let (changedTime, modifiedTime) = (value.st_ctimespec, value.st_mtimespec)
            #endif
            let changed = Double(changedTime.tv_sec) + Double(changedTime.tv_nsec) / 1e9
            let modified = Double(modifiedTime.tv_sec) + Double(modifiedTime.tv_nsec) / 1e9
            return max(changed, modified) < limit
        }
    }

    mutating func bind(_ roots: [CargoRelocation.Root]) {
        guard !roots.isEmpty else { return }
        entries = Set(entries + roots.map { Entry(kind: "root", name: $0.placeholder) })
            .sorted { ($0.kind, $0.name) < ($1.kind, $1.name) }
    }

    /// Adds variables the compiler's dep-info says the crate read (`env!`, `option_env!`).
    mutating func addEnvironmentDependencies(_ depInfo: String, keyedEnvironment: (String) -> Bool) {
        var all = Set(entries)
        for line in depInfo.split(separator: "\n") where line.hasPrefix("# env-dep:") {
            let name = String(line.dropFirst(10).prefix { $0 != "=" })
            if !keyedEnvironment(name) { all.insert(Entry(kind: "env", name: name)) }
        }
        entries = all.sorted { ($0.kind, $0.name) < ($1.kind, $1.name) }
    }

    /// The current state of every input, in order. Throws when an input cannot be read consistently.
    func evaluate(
        relocation: CargoRelocation, environment: [String: String], hasher: CargoInputHasher,
        volatileEnvironment: (String) -> Bool
    ) throws -> [String] {
        var result: [String] = []
        for entry in entries {
            switch entry.kind {
            case "env":
                result += ["env", entry.name, environment[entry.name].map { "=" + relocation.relative($0) } ?? "unset"]
            case "environment":
                result.append("environment")
                result += environment.filter { !volatileEnvironment($0.key) }.sorted { $0.key < $1.key }
                    .map { "\($0.key)=\(relocation.relative($0.value))" }
            case "root":
                result += ["root", entry.name, relocation.absolute(entry.name) ?? "unknown"]
            case "path", "listing":
                guard let path = relocation.absolute(entry.name) else { throw CargoCacheInvocation.CacheError.unsupported }
                result += [entry.kind, entry.name, try state(of: path, listing: entry.kind == "listing", hasher: hasher)]
            default:
                throw CargoCacheInvocation.CacheError.unsupported
            }
        }
        return result
    }

    private func state(of path: String, listing: Bool, hasher: CargoInputHasher) throws -> String {
        var value = stat()
        guard stat(path, &value) == 0 else { return "absent" }
        switch value.st_mode & S_IFMT {
        case S_IFDIR:
            guard listing else { return "directory" }
            let names = try FileManager.default.contentsOfDirectory(atPath: path).sorted()
            return "listing:" + REAPI.digest(Data(names.joined(separator: "\n").utf8)).hash
        case S_IFREG:
            let digest = try hasher.digest(URL(fileURLWithPath: path).resolvingSymlinksInPath(), shared: true)
            return "file:\(digest.hash):\(digest.sizeBytes)"
        default:
            return "special:\(value.st_mode & S_IFMT)"
        }
    }

    private static func standardized(_ path: String) -> String {
        CargoRelocation.canonical(path)
    }
}

/// Maps a declared key to the read set of a run with that key, locally and through the shared REAPI cache.
struct CargoReadIndex {
    let root: URL
    let declaredKey: REAPI.Digest
    let version: String

    private var command: Data {
        (try? REAPI.Command.with { $0.arguments = [version, "reads", declaredKey.hash, String(declaredKey.sizeBytes)] }
            .serializedData()) ?? Data()
    }

    private var action: Data {
        (try? REAPI.Action.with {
            $0.commandDigest = REAPI.digest(command)
            $0.inputRootDigest = REAPI.emptyBlob
        }.serializedData()) ?? Data()
    }

    private var local: URL { root.appendingPathComponent("reads/" + declaredKey.hash + ".json") }

    func get(remote: (any REAPICacheStoring)?) async -> CargoReadSet? {
        if let data = try? Data(contentsOf: local), let set = try? JSONDecoder().decode(CargoReadSet.self, from: data) {
            return set
        }
        guard let remote,
              let result = try? await remote.actionResult(for: REAPI.digest(action)),
              result.exitCode == 0, let file = result.outputFiles.first, file.path == "reads.json",
              file.digest.sizeBytes <= 16_000_000
        else { return nil }
        let staging = root.appendingPathComponent("staging/" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        try? FileManager.default.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? await remote.downloadBlobs([file.digest: staging]))?.available.contains(file.digest) == true,
              let data = try? Data(contentsOf: staging), REAPI.digest(data) == file.digest,
              let set = try? JSONDecoder().decode(CargoReadSet.self, from: data)
        else { return nil }
        try? write(data, to: local)
        return set
    }

    func put(_ set: CargoReadSet, remote: (any REAPICacheStoring)?, environment: [String: String]) async {
        guard let data = try? JSONEncoder().encode(set) else { return }
        try? write(data, to: local)
        guard let remote else { return }
        if let marker = CargoCacheSetup.readOnlyMarker(environment: environment),
           FileManager.default.fileExists(atPath: marker.path) { return }
        let staging = root.appendingPathComponent("staging/" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        var blobs: [REAPI.Digest: URL] = [:]
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            for (index, blob) in [data, command, action, Data()].enumerated() {
                let file = staging.appendingPathComponent("\(index)")
                try blob.write(to: file)
                blobs[REAPI.digest(blob)] = file
            }
            let upload = try await remote.uploadAvailableBlobs(blobs)
            guard upload.available.isSuperset(of: Set(blobs.keys)) else { return }
            var result = REAPI.ActionResult()
            result.outputFiles = [.with { $0.path = "reads.json"; $0.digest = REAPI.digest(data) }]
            try await remote.storeActionResult(result, for: REAPI.digest(action))
        } catch {}
    }

    private func write(_ data: Data, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}
