import Foundation

/// Cache inputs describe the evaluation, not checkout timestamps. Bind the result bytes
/// to those inputs as well, so interrupted or interleaved writes cannot certify an old dump.
enum ManifestCache {
    private struct Record: Codable {
        let inputs: String
        let output: String
    }

    actor ToolchainIdentity {
        private let probe: @Sendable () async throws -> String
        private var result: Task<String, Error>?

        init(probe: @escaping @Sendable () async throws -> String = ManifestCache.toolchainIdentity) {
            self.probe = probe
        }

        func value() async throws -> String {
            if let result { return try await result.value }
            let result = Task {
                try await probe()
            }
            self.result = result
            return try await result.value
        }
    }

    @TaskLocal static var toolchain: ToolchainIdentity?
    @TaskLocal static var scratchDirectory: URL?
    @TaskLocal static var rootPackageDirectory: URL?
    @TaskLocal static var sharedCacheDirectory: URL?

    static func withContext<T>(
        packageDirectory: URL,
        scratchDirectory: URL?,
        sharedCacheDirectory: URL? = nil,
        toolchain: ToolchainIdentity = ToolchainIdentity(),
        operation: () async throws -> T
    ) async throws -> T {
        return try await $toolchain.withValue(toolchain) {
            try await $rootPackageDirectory.withValue(packageDirectory.standardizedFileURL) {
                try await $scratchDirectory.withValue(scratchDirectory ?? packageDirectory.appendingPathComponent(".build")) {
                    try await $sharedCacheDirectory.withValue(
                        (try? Cache.resolvedRoot(sharedCacheDirectory))?.standardizedFileURL
                    ) {
                        try await operation()
                    }
                }
            }
        }
    }

    static func toolchainIdentity() async throws -> String {
        let version = try await SystemProcess.run(
            "/usr/bin/swift", ["--version"], customEnvironment: Environment.manifestValues
        )
        var identity = version.stdout
        #if os(macOS)
            let location = try await SystemProcess.run(
                "/usr/bin/xcrun", ["--find", "swiftc"], customEnvironment: Environment.manifestValues
            )
            identity += location.stdout
        #endif
        if let compiler = Environment.manifest["SWIFT_EXEC_MANIFEST"] {
            let manifestCompiler = try await SystemProcess.run(
                compiler, ["--version"], customEnvironment: Environment.manifestValues
            )
            identity += manifestCompiler.stdout
        }
        return Hashing.sha256Hex(identity)
    }

    static func inputs(packageDir: URL, disableSandbox: Bool) async throws -> String {
        try await ManifestEnvironmentFingerprint.digest(for: inputValues(packageDir: packageDir, disableSandbox: disableSandbox))
    }

    private static func inputValues(packageDir: URL, disableSandbox: Bool) async throws -> [String: String] {
        let identity: String
        if let toolchain {
            identity = try await toolchain.value()
        } else {
            identity = try await toolchainIdentity()
        }
        var inputs = [
            "schema": "1",
            "environment": await ManifestEnvironmentFingerprint.current(packageDir: packageDir),
            "toolchain": identity,
            "packagePath": packageDir.standardizedFileURL.path,
            "realPackagePath": PathCanonicalizer.realpath(packageDir).path,
            "disableSandbox": String(disableSandbox),
        ]
        // Hash every candidate, including its name: adding or removing a version-specific
        // manifest can change SwiftPM's selection without modifying Package.swift.
        for manifest in try await manifestCandidates(packageDir: packageDir) {
            inputs[manifest.lastPathComponent] = try await Hashing.sha256Hex(fileSystem.readFile(at: manifest.absolutePath))
            inputs["path:\(manifest.lastPathComponent)"] = PathCanonicalizer.realpath(manifest).path
        }
        guard inputs["Package.swift"] != nil else {
            throw ToolError.message("no Package.swift in \(packageDir.path)")
        }
        return inputs
    }

    /// The shared-cache entry for dumping `packageDir`, when it resolves into a pinned source
    /// snapshot of the shared cache. SwiftPM evaluates a manifest at its real path, so the dump of a
    /// snapshot does not depend on the scratch directory that links to it, and every scratch
    /// directory can reuse it. Directories copied into a scratch directory are not shared.
    static func sharedEntry(packageDir: URL, disableSandbox: Bool) async -> (file: URL, inputs: String)? {
        guard let sharedCacheDirectory else { return nil }
        let sources = PathCanonicalizer.realpath(sharedCacheDirectory.appendingPathComponent("sources")).path
        guard PathCanonicalizer.realpath(packageDir).path.hasPrefix(sources + "/"),
              var values = try? await inputValues(packageDir: packageDir, disableSandbox: disableSandbox)
        else { return nil }
        values.removeValue(forKey: "packagePath")
        let inputs = ManifestEnvironmentFingerprint.digest(for: values)
        let file = sharedCacheDirectory.appendingPathComponent("manifest-dumps")
            .appendingPathComponent(inputs).appendingPathComponent(ManifestLoader.cacheFile)
        return (file, inputs)
    }

    static func manifestCandidates(packageDir: URL) async throws -> [URL] {
        try await fileSystem.contentsOfDirectory(at: packageDir).filter {
            $0.lastPathComponent == "Package.swift"
                || ($0.lastPathComponent.hasPrefix("Package@swift-") && $0.pathExtension == "swift")
        }
    }

    static func read(at cache: URL, inputs: String) async -> Data? {
        guard let recordData = try? await fileSystem.readFile(at: sidecar(cache).absolutePath),
              let record = try? JSONDecoder().decode(Record.self, from: recordData),
              record.inputs == inputs,
              let data = try? await fileSystem.readFile(at: cache.absolutePath),
              record.output == Hashing.sha256Hex(data)
        else { return nil }
        return data
    }

    static func write(_ data: Data, at cache: URL, inputs: String?) async throws {
        // An older binary must re-evaluate this dump rather than accept the new bytes
        // using a legacy environment sidecar that describes the previous output.
        let legacySidecar = try ManifestEnvironmentFingerprint.sidecarPath(forCacheFile: cache.absolutePath)
        if try await fileSystem.exists(legacySidecar) {
            try await fileSystem.remove(legacySidecar)
        }
        if inputs == nil, try await fileSystem.exists(sidecar(cache).absolutePath) {
            try await fileSystem.remove(sidecar(cache).absolutePath)
        }
        try await fileSystem.atomicWrite(data, to: cache)
        guard let inputs else { return }
        try await fileSystem.atomicWrite(
            JSONEncoder().encode(Record(inputs: inputs, output: Hashing.sha256Hex(data))),
            to: sidecar(cache)
        )
    }

    static func sidecar(_ cache: URL) -> URL {
        cache.appendingPathExtension("inputs.json")
    }

    static func prune(scratchDirectory: URL, keeping packageDirectories: [URL]) async throws {
        let directory = scratchDirectory.appendingPathComponent("swifterpm/manifests/packages")
        guard try await fileSystem.exists(directory.absolutePath) else { return }
        let retained = Set(packageDirectories.map { Hashing.sha256Hex(Data($0.standardizedFileURL.path.utf8)) })
        for entry in try await fileSystem.contentsOfDirectory(at: directory) {
            let name = entry.lastPathComponent
            if name.count == 64, name.allSatisfy(\.isHexDigit), !retained.contains(name) {
                try await fileSystem.remove(entry.absolutePath)
            }
        }
    }
}
