import Foundation
import Path
import TuistREAPI
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// Keeps what Cargo built of registry and git dependencies (rlibs, build-script runs, fingerprints) so a fresh
/// target directory, here or on another machine, starts with them. Cargo stays the judge of freshness: restored
/// units carry Cargo's own fingerprints, so a unit whose inputs differ here is rebuilt, never reused.
struct CargoUnitCache {
    static let version = "tuist-swift-cargo-units-v3"

    let profile: URL
    let root: URL
    let command: Data
    let action: Data
    var actionDigest: REAPI.Digest { REAPI.digest(action) }
    let environment: [String: String]
    let targetDirectory: URL
    let workspaceRoot: URL
    let cargoHome: URL
    /// Units whose fingerprints predate this command are leftovers of earlier builds, which may not match it.
    let sessionStarted: Date
    let relocation: CargoRelocation
    var remote: (any REAPICacheStoring)?

    struct Manifest: Codable, Equatable {
        var units: [Unit]
    }

    struct Unit: Codable, Equatable {
        var name: String
        var directories: [String]
        var files: [File]
        /// Machine roots the unit's outputs name, such as a string from `env!("CARGO_MANIFEST_DIR")`; such a unit is
        /// restored only where those roots are the same.
        var bound: [String]?
    }

    struct File: Codable, Equatable {
        var path: String
        var hash: String
        var size: Int64
        var executable: Bool
        /// The per-crate cache admitted this artifact in the session that built it; restoring re-issues its
        /// session certificate so dependents remain cacheable.
        var certified: Bool?

        var digest: REAPI.Digest { .with { $0.hash = hash; $0.sizeBytes = size } }
    }

    // MARK: - Setup

    static func prepare(
        executable: String, arguments: [String], environment: [String: String], directory: AbsolutePath,
        process: CargoProcess
    ) async -> CargoUnitCache? {
        let invocation = CargoInvocation(arguments)
        guard let cache = environment["TUIST_CARGO_CACHE_DIR"],
              let command = invocation.command, let commandIndex = invocation.commandIndex,
              let kind = [
                  "build": "build",
                  "b": "build",
                  "run": "build",
                  "r": "build",
                  "check": "check",
                  "c": "check",
                  "test": "test",
                  "t": "test",
                  "bench": "bench",
              ][command],
              environment["CARGO_BUILD_TARGET"].map(\.isEmpty) ?? true,
              !arguments.prefix(while: { $0 != "--" }).contains(where: { $0 == "--target" || $0.hasPrefix("--target=") })
        else { return nil }
        let options = Array(arguments.prefix(while: { $0 != "--" }))
        var metadataArguments = ["metadata", "--format-version", "1", "--no-deps", "--offline"]
        if let manifest = value("--manifest-path", in: options) { metadataArguments += ["--manifest-path", manifest] }
        guard let metadata = try? await process.capture(
            executable, arguments: metadataArguments, environment: environment, directory: directory
        ),
            let json = try? JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any],
            let target = json["target_directory"] as? String, let workspace = json["workspace_root"] as? String,
            let lock = try? Data(contentsOf: URL(fileURLWithPath: workspace).appendingPathComponent("Cargo.lock")),
            let rustc = try? await process.capture(
                environment["RUSTC"] ?? "rustc", arguments: ["-vV"], environment: environment, directory: directory
            ),
            let sysroot = try? await process.capture(
                environment["RUSTC"] ?? "rustc", arguments: ["--print", "sysroot"], environment: environment,
                directory: directory
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        let profileName = profileDirectory(options: options, kind: kind)
        let flags = environment.filter { key, _ in
            ["RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS", "CARGO_BUILD_RUSTFLAGS", "CARGO_INCREMENTAL", "RUSTC_BOOTSTRAP"]
                .contains(key) || key.hasPrefix("CARGO_PROFILE_") || key.hasPrefix("CARGO_TARGET_")
        }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        let cargoHome = URL(fileURLWithPath: environment["CARGO_HOME"] ?? FileManager.default
            .homeDirectoryForCurrentUser.appendingPathComponent(".cargo").path).standardizedFileURL
        let inputs = [version, REAPI.digest(lock).hash, rustc, profileName, kind]
            + normalized(Array(options.dropFirst(commandIndex + 1))) + flags
            + configurations(from: URL(fileURLWithPath: directory.pathString), cargoHome: cargoHome)
        guard let encoded = try? JSONEncoder().encode(inputs),
              let command = try? REAPI.Command.with({ $0.arguments = [version, REAPI.digest(encoded).hash] })
              .serializedData(),
              let action = try? REAPI.Action.with({
                  $0.commandDigest = REAPI.digest(command)
                  $0.inputRootDigest = REAPI.emptyBlob
              }).serializedData()
        else { return nil }
        let targetDirectory = URL(fileURLWithPath: target).standardizedFileURL
        return CargoUnitCache(
            profile: targetDirectory.appendingPathComponent(profileName),
            root: URL(fileURLWithPath: cache),
            command: command,
            action: action,
            environment: environment,
            targetDirectory: targetDirectory,
            workspaceRoot: URL(fileURLWithPath: workspace).standardizedFileURL,
            cargoHome: cargoHome,
            sessionStarted: Date(),
            relocation: CargoRelocation(
                environment: environment.merging(
                    ["TUIST_CARGO_TARGET_DIR": target, "TUIST_CARGO_WORKSPACE_ROOT": workspace]
                ) { $1 },
                sysroot: URL(fileURLWithPath: sysroot).standardizedFileURL
            ),
            remote: nil
        )
    }

    /// Cargo's configuration files, nearest first, as Cargo discovers them: their profiles, flags and target
    /// settings select different units. Files Cargo would ignore only make keys more specific.
    static func configurations(from directory: URL, cargoHome: URL) -> [String] {
        var result: [String] = []
        var current = directory.standardizedFileURL
        var candidates: [URL] = []
        while true {
            candidates += ["config.toml", "config"].map { current.appendingPathComponent(".cargo/" + $0) }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        candidates += ["config.toml", "config"].map { cargoHome.appendingPathComponent($0) }
        for file in candidates {
            // Contents only, in discovery order: a checkout's own configuration must not tie keys to its path.
            if let data = try? Data(contentsOf: file) { result.append("config=" + REAPI.digest(data).hash) }
        }
        return result
    }

    static func profileDirectory(options: [String], kind: String) -> String {
        if options.contains("--release") || options.contains("-r") { return "release" }
        if let profile = value("--profile", in: options) {
            return ["dev": "debug", "test": "debug", "release": "release", "bench": "release"][profile] ?? profile
        }
        return kind == "bench" ? "release" : "debug"
    }

    /// Options that only change Cargo's presentation, scheduling or network use do not select different units.
    static func normalized(_ options: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < options.count {
            let option = options[index]
            if ["--color", "-j", "--jobs", "--message-format"].contains(option) { index += 2; continue }
            if ["-q", "--quiet", "-v", "-vv", "--verbose", "--offline", "--locked", "--frozen"].contains(option)
                || ["--color=", "--jobs=", "--message-format="].contains(where: option.hasPrefix)
                || (option.hasPrefix("-j") && option.dropFirst(2).allSatisfy(\.isNumber))
            {
                index += 1; continue
            }
            result.append(option)
            index += 1
        }
        return result
    }

    private static func value(_ name: String, in options: [String]) -> String? {
        if let index = options.firstIndex(of: name), index + 1 < options.count { return options[index + 1] }
        return options.first(where: { $0.hasPrefix(name + "=") }).map { String($0.dropFirst(name.count + 1)) }
    }
}

extension CargoUnitCache {
    // MARK: - Restoration

    /// Restores the units the manifest lists that the target directory lacks. Returns how many were restored.
    @discardableResult
    func restore() async -> Int {
        guard let manifest = await manifest() else {
            debug("no dependency unit manifest")
            return 0
        }
        let missing = manifest.units.filter {
            Self.isSafe($0) && Set($0.bound ?? []).isSubset(of: relocation.roots.map(\.path))
                && !FileManager.default.fileExists(atPath: profile.appendingPathComponent(".fingerprint/" + $0.name).path)
        }
        guard !missing.isEmpty else {
            debug("all \(manifest.units.count) dependency units are present")
            return 0
        }
        var needed: [REAPI.Digest: URL] = [:]
        let staging = root.appendingPathComponent("staging/" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        for unit in missing {
            for file in unit.files where !hasBlob(file.digest) {
                needed[file.digest] = staging.appendingPathComponent(file.hash)
            }
        }
        if !needed.isEmpty {
            guard let remote else {
                debug("\(needed.count) unit blobs are missing locally and there is no remote")
                return 0
            }
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let downloaded = try await remote.downloadBlobs(needed)
                for (digest, file) in needed where downloaded.available.contains(digest) {
                    if (try? REAPI.digest(file: file)) == digest { _ = try? publish(file, digest: digest) }
                }
            } catch {
                debug("unit download failed: \(REAPI.describe(error))")
            }
        }
        return withBuildLock {
            // One modification time for every restored file: Cargo compares dependency outputs against dependents
            // and dep-info inputs against `invoked.timestamp`, and only a strictly newer file is stale.
            let restoredAt = Date()
            var restored = 0
            for unit in missing where unit.files.allSatisfy({ hasBlob($0.digest) }) {
                if materialize(unit, at: restoredAt) { restored += 1 }
            }
            debug("restored \(restored) of \(manifest.units.count) dependency units")
            return restored
        } ?? 0
    }

    private func manifest() async -> Manifest? {
        let index = root.appendingPathComponent("unit-actions/" + actionDigest.hash)
        var result = (try? Data(contentsOf: index)).flatMap { try? REAPI.ActionResult(serializedBytes: $0) }
        if result == nil, let remote {
            do { result = try await remote.actionResult(for: actionDigest) } catch {
                debug("unit manifest lookup failed: \(REAPI.describe(error))")
            }
        }
        guard let result, result.exitCode == 0, result.outputFiles.count == 1,
              let output = result.outputFiles.first, output.path == "units.json",
              output.digest.sizeBytes <= 64_000_000
        else { return nil }
        if !hasBlob(output.digest), let remote {
            let file = root.appendingPathComponent("staging/" + UUID().uuidString)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: file) }
            if (try? await remote.downloadBlobs([output.digest: file]))?.available.contains(output.digest) == true,
               (try? REAPI.digest(file: file)) == output.digest
            {
                _ = try? publish(file, digest: output.digest)
            }
        }
        guard hasBlob(output.digest), let data = try? Data(contentsOf: blobPath(output.digest)),
              REAPI.digest(data) == output.digest,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return nil }
        try? write(result.serializedData(), to: index)
        return manifest
    }

    /// Writes a unit's outputs before its fingerprint, so an interrupted restoration leaves a unit Cargo rebuilds.
    private func materialize(_ unit: Unit, at date: Date) -> Bool {
        let ordered = unit.files.filter { !$0.path.hasPrefix(".fingerprint/") } + unit.files
            .filter { $0.path.hasPrefix(".fingerprint/") }
        do {
            for directory in unit.directories {
                try FileManager.default.createDirectory(
                    at: profile.appendingPathComponent(directory), withIntermediateDirectories: true
                )
            }
            for file in ordered {
                let destination = profile.appendingPathComponent(file.path)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                let temporary = destination.deletingLastPathComponent().appendingPathComponent(".tuist-" + UUID().uuidString)
                try FileManager.default.copyItem(at: blobPath(file.digest), to: temporary)
                markUsed(file.digest)
                guard try REAPI.digest(file: temporary) == file.digest else {
                    try? FileManager.default.removeItem(at: temporary)
                    throw REAPICacheError.corruptBlob
                }
                try FileManager.default.setAttributes(
                    [.posixPermissions: file.executable ? 0o755 : 0o644, .modificationDate: date],
                    ofItemAtPath: temporary.path
                )
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporary, to: destination)
                if file.certified == true, let proof = CargoCacheInputs.proofPath(file.digest, environment: environment) {
                    try? FileManager.default.createDirectory(
                        at: proof.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try? Data(CargoCacheInvocation.keyVersion.utf8).write(to: proof, options: .atomic)
                }
            }
            return true
        } catch {
            try? FileManager.default.removeItem(at: profile.appendingPathComponent(".fingerprint/" + unit.name))
            debug("unit \(unit.name) was not restored: \(error)")
            return false
        }
    }

    private static func isSafe(_ unit: Unit) -> Bool {
        guard isUnitName(unit.name) else { return false }
        return (unit.directories + unit.files.map(\.path)).allSatisfy { path in
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            return !path.hasPrefix("/") && [".fingerprint", "build", "deps"].contains(String(components.first ?? ""))
                && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
        } && unit.files.allSatisfy { (try? REAPI.validate($0.digest)) != nil }
    }

    private static func isUnitName(_ name: String) -> Bool {
        guard let separator = name.lastIndex(of: "-") else { return false }
        let hash = name[name.index(after: separator)...]
        return hash.count == 16 && hash.allSatisfy(\.isHexDigit) && !name.contains("/") && name.first != "."
    }
}

extension CargoUnitCache {
    // MARK: - Publication

    /// Records the registry and git dependency units in the target directory and publishes their manifest.
    func store() async {
        guard let units = withBuildLock({ collectUnits() }), !units.isEmpty else { return }
        let manifest = Manifest(units: units.sorted { $0.name < $1.name })
        guard let data = try? JSONEncoder().encode(manifest), data.count <= 64_000_000 else { return }
        let digest = REAPI.digest(data)
        var result = REAPI.ActionResult()
        result.outputFiles = [.with { $0.path = "units.json"; $0.digest = digest }]
        let index = root.appendingPathComponent("unit-actions/" + actionDigest.hash)
        let previous = (try? Data(contentsOf: index)).flatMap { try? REAPI.ActionResult(serializedBytes: $0) }
        let staging = root.appendingPathComponent("staging/" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let file = staging.appendingPathComponent("units.json")
            try data.write(to: file)
            _ = try publish(file, digest: digest)
            try write(result.serializedData(), to: index)
        } catch { return }
        guard previous?.outputFiles.first?.digest != digest, let remote else { return }
        if let marker = CargoCacheSetup.readOnlyMarker(environment: environment),
           FileManager.default.fileExists(atPath: marker.path) { return }
        var blobs: [REAPI.Digest: URL] = [digest: blobPath(digest)]
        for unit in units {
            for file in unit.files {
                blobs[file.digest] = blobPath(file.digest)
            }
        }
        do {
            for (index, data) in [command, action, Data()].enumerated() {
                let file = staging.appendingPathComponent("request-\(index)")
                try data.write(to: file)
                blobs[REAPI.digest(data)] = file
            }
            let upload = try await remote.uploadAvailableBlobs(blobs)
            guard upload.available.isSuperset(of: Set(blobs.keys)) else {
                debug("unit upload incomplete: \(upload.failures.values.sorted().first ?? "unknown")")
                return
            }
            try await remote.storeActionResult(result, for: actionDigest)
            debug("published \(units.count) dependency units")
        } catch {
            debug("unit publication failed: \(REAPI.describe(error))")
        }
    }

    private func collectUnits() -> [Unit] {
        let fingerprints = profile.appendingPathComponent(".fingerprint")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: fingerprints.path) else { return [] }
        let deps = (try? FileManager.default.contentsOfDirectory(atPath: profile.appendingPathComponent("deps").path)) ?? []
        let candidates = names.filter(Self.isUnitName).prefix(10000)
        // A unit is a dependency's when every source its compiler read is in Cargo's registry or git checkouts
        // (or generated into this target directory). Build-script runs read nothing through rustc: they belong to
        // a package only when all of that package's compiled units are dependencies.
        var classified: [String: Bool] = [:]
        for name in candidates {
            let hash = String(name.suffix(16))
            let depInfo = deps.filter { $0.hasSuffix("-\(hash).d") }.map { profile.appendingPathComponent("deps/" + $0) }
                + ((try? FileManager.default.contentsOfDirectory(atPath: profile.appendingPathComponent("build/" + name).path))
                    ?? []).filter { $0.hasSuffix("-\(hash).d") }.map { profile.appendingPathComponent("build/\(name)/" + $0) }
            guard !depInfo.isEmpty else { continue }
            classified[name] = depInfo.allSatisfy(isDependencySource)
        }
        func package(_ name: String) -> String { String(name.dropLast(17)) }
        var packages: [String: Bool] = [:]
        for (name, dependency) in classified {
            packages[package(name), default: true] = packages[package(name), default: true] && dependency
        }
        var units: [Unit] = []
        var budget: Int64 = 8_000_000_000
        for name in candidates {
            let created = (try? fingerprints.appendingPathComponent(name).resourceValues(forKeys: [.creationDateKey]))?
                .creationDate
            guard let created, created >= sessionStarted.addingTimeInterval(-1) else { continue }
            let isDependency = classified[name] ?? (packages[package(name)] == true && isPortableRun(name))
            guard isDependency, let unit = collect(name, deps: deps, budget: &budget) else { continue }
            units.append(unit)
        }
        return units
    }

    private func isDependencySource(_ depInfo: URL) -> Bool {
        guard (try? depInfo.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap({ $0 }).map({ $0 < 2_000_000 }) == true,
              let text = try? String(contentsOf: depInfo, encoding: .utf8),
              let sources = try? CargoCacheInvocation.dependencies(text), !sources.isEmpty
        else { return false }
        let roots = ["registry/src/", "git/checkouts/"].map { cargoHome.path + "/" + $0 }
        var sawDependency = false
        for source in sources {
            let path = URL(fileURLWithPath: source).standardizedFileURL.path
            if roots.contains(where: path.hasPrefix) { sawDependency = true; continue }
            if path.hasPrefix(targetDirectory.path + "/") { continue }
            return false
        }
        return sawDependency
    }

    /// A build-script run is portable when Cargo can relocate its output: its recorded `OUT_DIR` prefix is rewritten
    /// by Cargo, but other paths into this checkout or Cargo home, and absolute `rerun-if-changed` paths whose
    /// timestamps a restored unit would outdate, are not.
    private func isPortableRun(_ name: String) -> Bool {
        let directory = profile.appendingPathComponent("build/" + name)
        guard let output = try? String(contentsOf: directory.appendingPathComponent("output"), encoding: .utf8),
              let outDirectory = try? String(contentsOf: directory.appendingPathComponent("root-output"), encoding: .utf8)
        else { return false }
        let remaining = output.replacingOccurrences(of: outDirectory.trimmingCharacters(in: .newlines), with: "")
        guard ![workspaceRoot.path, cargoHome.path, targetDirectory.path].contains(where: remaining.contains)
        else { return false }
        let fingerprint = profile.appendingPathComponent(".fingerprint/" + name)
        let records = ((try? FileManager.default.contentsOfDirectory(atPath: fingerprint.path)) ?? [])
            .filter { $0.hasSuffix(".json") }
        guard !records.isEmpty else { return false }
        return records.allSatisfy { record in
            guard let data = try? Data(contentsOf: fingerprint.appendingPathComponent(record)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let local = json["local"] as? [[String: Any]] else { return false }
            return local.allSatisfy { entry in
                guard let rerun = entry["RerunIfChanged"] as? [String: Any] else { return true }
                return (rerun["paths"] as? [String])?.allSatisfy { !$0.hasPrefix("/") } == true
            }
        }
    }

    private func collect(_ name: String, deps: [String], budget: inout Int64) -> Unit? {
        let hash = String(name.suffix(16))
        var paths = deps.filter { file in
            guard let range = file.range(of: "-" + hash) else { return false }
            return range.upperBound == file.endIndex || file[range.upperBound] == "."
        }.map { "deps/" + $0 }
        var directories: [String] = []
        for tree in [".fingerprint/" + name, "build/" + name] {
            let base = profile.appendingPathComponent(tree)
            guard FileManager.default.fileExists(atPath: base.path) else { continue }
            directories.append(tree)
            guard let entries = FileManager.default.enumerator(atPath: base.path) else { return nil }
            for case let entry as String in entries {
                let path = tree + "/" + entry
                let properties = try? profile.appendingPathComponent(path)
                    .resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if properties?.isSymbolicLink == true { return nil }
                if properties?.isDirectory == true { directories.append(path) } else { paths.append(path) }
            }
        }
        var files: [File] = []
        var bound: Set<String> = []
        // Cargo's own records and rustc's dep-info name paths by design; Cargo relocates a run's `OUT_DIR` itself.
        let records = ["output", "root-output", "stderr", "invoked.timestamp"]
        for path in paths.sorted() {
            let file = profile.appendingPathComponent(path)
            guard let properties = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  properties.isRegularFile == true, properties.isSymbolicLink != true,
                  let size = properties.fileSize, Int64(size) <= budget,
                  let digest = try? REAPI.digest(file: file), (try? publish(file, digest: digest)) != nil
            else { return nil }
            budget -= Int64(size)
            if !path.hasPrefix(".fingerprint/"), !path.hasSuffix(".d"),
               !(path.hasPrefix("build/") && records.contains(URL(fileURLWithPath: path).lastPathComponent))
            {
                guard let data = try? Data(contentsOf: file) else { return nil }
                bound.formUnion(relocation.boundRoots(in: data).map(\.path))
            }
            let certified = CargoCacheInputs.proofPath(digest, environment: environment)
                .map { FileManager.default.fileExists(atPath: $0.path) } == true
            files.append(File(
                path: path,
                hash: digest.hash,
                size: digest.sizeBytes,
                executable: FileManager.default.isExecutableFile(atPath: file.path),
                certified: certified ? true : nil
            ))
        }
        guard files.contains(where: { $0.path.hasPrefix(".fingerprint/") }) else { return nil }
        return Unit(
            name: name, directories: directories.sorted(), files: files, bound: bound.isEmpty ? nil : bound.sorted()
        )
    }
}

extension CargoUnitCache {
    // MARK: - Storage

    private func blobPath(_ digest: REAPI.Digest) -> URL { root.appendingPathComponent("blobs/" + digest.hash) }

    private func hasBlob(_ digest: REAPI.Digest) -> Bool {
        (try? blobPath(digest).resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } == Int(exactly: digest.sizeBytes)
    }

    /// Blobs carry the time they were last stored or restored, never their source's: build scripts copy
    /// files out of crate archives with years-old timestamps, which the cache's age-based pruning would evict.
    private func publish(_ file: URL, digest: REAPI.Digest) throws -> URL {
        let destination = blobPath(digest)
        if hasBlob(digest) {
            markUsed(digest)
            return destination
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: file, to: temporary)
        guard try REAPI.digest(file: temporary) == digest else { throw REAPICacheError.corruptBlob }
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: temporary.path)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    private func markUsed(_ digest: REAPI.Digest) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: blobPath(digest).path)
    }

    private func write(_ data: Data, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    /// Holds Cargo's own build lock for the profile directory, so no concurrent Cargo build observes partial units.
    private func withBuildLock<T>(_ body: () -> T) -> T? {
        guard (try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)) != nil
        else { return nil }
        let lock = open(profile.appendingPathComponent(".cargo-lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard lock >= 0 else { return nil }
        defer { close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { return nil }
        return body()
    }

    private func debug(_ message: String) {
        if environment["TUIST_DEBUG"] == "1" {
            FileHandle.standardError.write(Data("Tuist Cargo cache: \(message)\n".utf8))
        }
    }
}
