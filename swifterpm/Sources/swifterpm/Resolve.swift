import Foundation

enum PackageResolver {
    static func resolve(
        packageDir: URL,
        scratchDir: URL? = nil,
        cache: Cache,
        registryConfig _: RegistryConfig,
        registryConfigurationPath: URL? = nil,
        defaultRegistryURL: String? = nil,
        disableSandbox: Bool,
        scmToRegistryTransformation: SCMToRegistryTransformation = .disabled,
        useExistingResolvedFile: Bool = true,
        writeResolvedFile: Bool = true,
        progress: ResolutionProgressReporter? = nil
    ) async throws -> ResolvedPins {
        let manifest = try await ManifestLoader.dumpPackage(
            packageDir: packageDir, disableSandbox: disableSandbox
        )
        var manifestDependencies = try ManifestParser.dependencies(manifest)
        let localPackages = try await ManifestFileSystemDependencyGraph.collect(
            rootPackageDir: packageDir,
            rootManifest: manifest,
            disableSandbox: disableSandbox
        )
        for localPackage in localPackages {
            manifestDependencies.append(contentsOf: try ManifestParser.dependencies(localPackage.manifest))
        }
        let dependencies = manifestDependencies
        let originHash = try await originHash(packageDir: packageDir)
        guard !dependencies.isEmpty else {
            // Match SwiftPM's `saveResolvedFile` schema selection: V3 (with
            // originHash) for tools > 5.9, V2 for >= 5.6, V1 otherwise.
            // `ResolvedFile.write` removes the file when pins is empty, so this
            // version is only observed by in-memory consumers — but we still
            // match SwiftPM's choice rather than hardcoding one.
            let toolsVersion = try await packageToolsVersion(packageDir: packageDir)
            let resolved = ResolvedPins(
                originHash: originHash,
                pins: [],
                version: resolvedFileSchemaVersion(toolsVersion: toolsVersion)
            )
            if writeResolvedFile {
                try await ResolvedFile.write(packageDir: packageDir, resolved: resolved)
            }
            return resolved
        }

        progress?.started(
            rootVersionedDependencies: dependencies.filter {
                ManifestParser.versionRange(for: $0.requirement) != nil
            }.count,
            fixedDependencies: dependencies.filter {
                ManifestParser.versionRange(for: $0.requirement) == nil
            }.count
        )

        var resolved = try await resolveWithSwiftPackageManagerProcess(
            packageDir: packageDir,
            scratchDir: scratchDir,
            cacheDir: cache.root,
            registryConfigurationPath: registryConfigurationPath,
            defaultRegistryURL: defaultRegistryURL,
            disableSandbox: disableSandbox,
            scmToRegistryTransformation: scmToRegistryTransformation,
            useExistingResolvedFile: useExistingResolvedFile,
            writeResolvedFile: writeResolvedFile,
            forwardOutput: progress != nil
        )
        resolved.originHash = originHash
        resolved.pins = dedupePinsByIdentity(resolved.pins)
        resolved = resolved.normalizedForResolvedFile()
        if writeResolvedFile {
            // SwiftPM writes Package.resolved with its own originHash; rewrite
            // with ours so consumers can detect manifest changes.
            try await ResolvedFile.write(packageDir: packageDir, resolved: resolved)
        }
        progress?.finished(pinCount: resolved.pins.count)
        return resolved
    }

    private struct ResolvedFileSnapshot {
        let data: Data?
    }

    private static func resolveWithSwiftPackageManagerProcess(
        packageDir: URL,
        scratchDir: URL?,
        cacheDir: URL,
        registryConfigurationPath: URL?,
        defaultRegistryURL: String?,
        disableSandbox: Bool,
        scmToRegistryTransformation: SCMToRegistryTransformation,
        useExistingResolvedFile: Bool,
        writeResolvedFile: Bool,
        forwardOutput: Bool
    ) async throws -> ResolvedPins {
        let resolvedPath = packageDir.appendingPathComponent("Package.resolved")
        let snapshot =
            (!writeResolvedFile || !useExistingResolvedFile)
                ? try await snapshotResolvedFile(at: resolvedPath) : nil
        if !useExistingResolvedFile {
            try? await fileSystem.removePath(resolvedPath)
        }

        do {
            try await SystemProcess.run(
                "swift",
                swiftPackageResolveArguments(
                    packageDir: packageDir,
                    scratchDir: scratchDir,
                    cacheDir: cacheDir,
                    registryConfigurationPath: registryConfigurationPath,
                    defaultRegistryURL: defaultRegistryURL,
                    disableSandbox: disableSandbox,
                    scmToRegistryTransformation: scmToRegistryTransformation
                ),
                workingDirectory: packageDir,
                forwardOutput: forwardOutput
            )
            let resolved = try await ResolvedFile.read(packageDir: packageDir)
            if !writeResolvedFile, let snapshot {
                try await restoreResolvedFile(snapshot, at: resolvedPath)
            }
            return resolved
        } catch {
            if let snapshot {
                try? await restoreResolvedFile(snapshot, at: resolvedPath)
            }
            throw error
        }
    }

    private static func swiftPackageResolveArguments(
        packageDir: URL,
        scratchDir: URL?,
        cacheDir: URL,
        registryConfigurationPath: URL?,
        defaultRegistryURL: String?,
        disableSandbox: Bool,
        scmToRegistryTransformation: SCMToRegistryTransformation
    ) -> [String] {
        var arguments = [
            "package",
            "--package-path",
            packageDir.path,
            "--cache-path",
            cacheDir.path,
        ]
        if let scratchDir {
            arguments.append(contentsOf: ["--scratch-path", scratchDir.path])
        }
        if let registryConfigurationPath {
            arguments.append(contentsOf: ["--config-path", registryConfigurationPath.path])
        }
        if let defaultRegistryURL {
            arguments.append(contentsOf: ["--default-registry-url", defaultRegistryURL])
        }
        if disableSandbox {
            arguments.append("--disable-sandbox")
        }
        switch scmToRegistryTransformation {
        case .disabled:
            arguments.append("--disable-scm-to-registry-transformation")
        case .useRegistryIdentityForSCM:
            arguments.append("--use-registry-identity-for-scm")
        case .replaceSCMWithRegistry:
            arguments.append("--replace-scm-with-registry")
        }
        arguments.append("resolve")
        return arguments
    }

    private static func snapshotResolvedFile(at path: URL) async throws -> ResolvedFileSnapshot {
        guard try await fileSystem.exists(path.absolutePath) else {
            return ResolvedFileSnapshot(data: nil)
        }
        return ResolvedFileSnapshot(data: try await fileSystem.readFile(at: path.absolutePath))
    }

    private static func restoreResolvedFile(_ snapshot: ResolvedFileSnapshot, at path: URL) async throws {
        if let data = snapshot.data {
            try await fileSystem.atomicWrite(data, to: path)
        } else {
            try await fileSystem.removePath(path)
        }
    }

    /// Load the resolved pins for `packageDir`, resolving fresh only when
    /// needed. Centralizes the read-only / current-file / seed-and-resolve
    /// decision so every entry point (and any `SwifterPMCore` embedder) seeds
    /// the solver identically instead of re-resolving from scratch.
    static func resolveOrLoad(
        packageDir: URL,
        scratchDir: URL? = nil,
        cache: Cache,
        registryConfig: RegistryConfig,
        registryConfigurationPath: URL? = nil,
        defaultRegistryURL: String? = nil,
        disableSandbox: Bool,
        scmToRegistryTransformation: SCMToRegistryTransformation,
        preferResolvedFile: Bool,
        readOnly: Bool,
        skipUpdate: Bool,
        writeResolvedFile: Bool,
        progress: ResolutionProgressReporter?
    ) async throws -> ResolvedPins {
        let resolvedFileURL = packageDir.appendingPathComponent("Package.resolved")
        let resolvedFileExists = try await fileSystem.exists(resolvedFileURL.absolutePath)
        if readOnly {
            guard resolvedFileExists else {
                throw ToolError.message(
                    "Package.resolved is required when forcing resolved versions, but no file exists at \(resolvedFileURL.path)"
                )
            }
            return try await ResolvedFile.read(packageDir: packageDir)
        }
        // `--skip-update` is an explicit "trust the on-disk pins" signal:
        // read the file as-is even when it predates the `originHash` field
        // (SwiftPM Package.resolved v2). Tightening this to `readIfCurrent`
        // would silently fall through to a full resolve for every v2 file.
        if skipUpdate, resolvedFileExists {
            return try await ResolvedFile.read(packageDir: packageDir)
        }
        if preferResolvedFile,
           let existing = try await ResolvedFile.readIfCurrent(packageDir: packageDir)
        {
            return try await normalizeLoadedResolvedFile(
                existing, packageDir: packageDir, writeResolvedFile: writeResolvedFile
            )
        }
        // Mirror SwiftPM: `resolve` seeds the solver with the existing
        // Package.resolved (even a stale one) so only pins that no longer
        // satisfy the manifest change; `update` resolves from scratch. The
        // file is missing or stale here; if it exists, parse it strictly so a
        // corrupted Package.resolved surfaces instead of silently degrading
        // to an empty seed.
        let useExistingResolvedFile: Bool
        if preferResolvedFile, resolvedFileExists {
            _ = try await ResolvedFile.read(packageDir: packageDir)
            useExistingResolvedFile = true
        } else {
            useExistingResolvedFile = false
        }
        return try await resolve(
            packageDir: packageDir,
            scratchDir: scratchDir,
            cache: cache,
            registryConfig: registryConfig,
            registryConfigurationPath: registryConfigurationPath,
            defaultRegistryURL: defaultRegistryURL,
            disableSandbox: disableSandbox,
            scmToRegistryTransformation: scmToRegistryTransformation,
            useExistingResolvedFile: useExistingResolvedFile,
            writeResolvedFile: writeResolvedFile,
            progress: progress
        )
    }

    private static func normalizeLoadedResolvedFile(
        _ resolved: ResolvedPins,
        packageDir: URL,
        writeResolvedFile: Bool
    ) async throws -> ResolvedPins {
        let normalized = resolved.normalizedForResolvedFile()
        if writeResolvedFile {
            try await ResolvedFile.write(packageDir: packageDir, resolved: normalized)
        }
        return normalized
    }

    static func dedupePinsByIdentity(_ pins: [ResolvedPin]) -> [ResolvedPin] {
        var order: [String] = []
        var chosen: [String: ResolvedPin] = [:]
        for pin in pins {
            let key = pin.identity.lowercased()
            if let existing = chosen[key] {
                if existing.state.version == nil, pin.state.version != nil {
                    chosen[key] = pin
                }
            } else {
                order.append(key)
                chosen[key] = pin
            }
        }
        return order.compactMap { chosen[$0] }
    }

    static func localSourceControlPackageLocation(_ location: String) async throws -> URL? {
        let url: URL
        if let fileURL = URL(string: location), fileURL.isFileURL {
            url = fileURL
        } else if location.hasPrefix("/") {
            url = URL(fileURLWithPath: location)
        } else {
            return nil
        }

        guard try await fileSystem.exists(url.appendingPathComponent("Package.swift").absolutePath) else {
            return nil
        }
        return url.standardizedFileURL
    }

    static func sourceControlKind(location: String) async throws -> String {
        let local = try await localSourceControlPackageLocation(location)
        return local == nil ? "remoteSourceControl" : "localSourceControl"
    }

    private static func originHash(packageDir: URL) async throws -> String {
        // Matches SwiftPM's `computeResolvedFileOriginHash`: for our single-
        // package, no-extra-root-dependencies invocation shape, that function
        // reduces to sha256 over the root Package.swift bytes.
        Hashing.sha256Hex(
            try await fileSystem.readFile(
                at: packageDir.appendingPathComponent("Package.swift").absolutePath))
    }

    private static func packageToolsVersion(packageDir: URL) async throws -> (major: Int, minor: Int)? {
        let data = try await fileSystem.readFile(
            at: packageDir.appendingPathComponent("Package.swift").absolutePath)
        guard let firstLine = String(data: data, encoding: .utf8)?
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
        else { return nil }
        let prefix = "swift-tools-version"
        guard let colon = firstLine.range(of: prefix),
              let version = firstLine[colon.upperBound...]
              .drop(while: { $0 == ":" || $0.isWhitespace })
              .split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
              .prefix(2)
              .map(String.init) as [String]?,
              version.count >= 2,
              let major = Int(version[0]),
              let minor = Int(version[1].prefix(while: { $0.isNumber }))
        else { return nil }
        return (major, minor)
    }

    private static func resolvedFileSchemaVersion(toolsVersion: (major: Int, minor: Int)?) -> Int {
        guard let toolsVersion else { return 3 }
        if toolsVersion.major > 5 || (toolsVersion.major == 5 && toolsVersion.minor > 9) {
            return 3
        }
        if toolsVersion.major == 5, toolsVersion.minor >= 6 {
            return 2
        }
        return 1
    }
}
