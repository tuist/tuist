import Foundation

/// Cache inputs describe the evaluation, not checkout timestamps. Bind the result bytes
/// to those inputs as well, so interrupted or interleaved writes cannot certify an old dump.
enum ManifestCache {
    private struct Record: Codable {
        let inputs: String
        let output: String
    }

    @TaskLocal static var toolchain: String?
    @TaskLocal static var scratchDirectory: URL?
    @TaskLocal static var rootPackageDirectory: URL?

    static func withContext<T>(
        packageDirectory: URL,
        scratchDirectory: URL?,
        reportTimings: Bool = false,
        operation: () async throws -> T
    ) async throws -> T {
        var timing = ResolutionTiming(enabled: reportTimings)
        let identity = try? await toolchainIdentity()
        timing.finish("toolchain")
        return try await $toolchain.withValue(identity) {
            try await $rootPackageDirectory.withValue(packageDirectory.standardizedFileURL) {
                try await $scratchDirectory.withValue(scratchDirectory ?? packageDirectory.appendingPathComponent(".build")) {
                    try await ResolutionTiming.$isEnabled.withValue(reportTimings) {
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
        let identity: String
        if let toolchain {
            identity = toolchain
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
        let manifests = try await fileSystem.contentsOfDirectory(at: packageDir).filter {
            $0.lastPathComponent == "Package.swift"
                || ($0.lastPathComponent.hasPrefix("Package@swift-") && $0.pathExtension == "swift")
        }
        for manifest in manifests {
            inputs[manifest.lastPathComponent] = try await Hashing.sha256Hex(fileSystem.readFile(at: manifest.absolutePath))
            inputs["path:\(manifest.lastPathComponent)"] = PathCanonicalizer.realpath(manifest).path
        }
        guard inputs["Package.swift"] != nil else {
            throw ToolError.message("no Package.swift in \(packageDir.path)")
        }
        return ManifestEnvironmentFingerprint.digest(for: inputs)
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
}
