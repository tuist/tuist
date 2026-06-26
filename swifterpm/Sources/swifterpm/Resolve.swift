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
            let resolved = try await ResolvedFile.read(packageDir: packageDir)
            try await validateResolvedFileSatisfiesManifest(
                resolved, packageDir: packageDir, disableSandbox: disableSandbox
            )
            return resolved
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

    /// SwiftPM refuses to build against a `Package.resolved` whose pins no
    /// longer satisfy the manifest when automatic resolution is disabled
    /// (`--force-resolved-versions` / `--disable-automatic-resolution`); it
    /// errors with an "out-of-date resolved file" instead of silently using the
    /// stale pins. The `readOnly` path skipped that check, so a manifest bumped
    /// past its lockfile (e.g. an `exact:` raised without re-resolving) was
    /// restored to the old version and reported success — diverging from
    /// SwiftPM and masking the very drift the flag is meant to catch.
    ///
    /// SwiftPM implements this in `ResolverPrecomputationProvider`: it runs the
    /// resolver with each package's *only* available version fixed to its pin
    /// (`LocalPackageContainer.versionsAscending` returns `[pinnedVersion]`), so
    /// a `.required` result — and the error — fires when a pin can't satisfy a
    /// constraint, not merely because a newer version exists within a still-
    /// satisfied range.
    ///
    /// This is the fast, fail-fast half: it validates only the root manifest's
    /// direct dependencies, so it needs no checkouts and runs before the restore.
    /// `validateResolvedGraphSatisfiesManifests` runs after the restore and
    /// extends the same satisfiability check across the whole pinned graph
    /// (transitive constraints included) for full SwiftPM parity.
    private static func validateResolvedFileSatisfiesManifest(
        _ resolved: ResolvedPins,
        packageDir: URL,
        disableSandbox: Bool
    ) async throws {
        let manifest = try await ManifestLoader.dumpPackage(
            packageDir: packageDir, disableSandbox: disableSandbox
        )
        var dependencies = try ManifestParser.dependencies(manifest)
        let localPackages = try await ManifestFileSystemDependencyGraph.collect(
            rootPackageDir: packageDir,
            rootManifest: manifest,
            disableSandbox: disableSandbox
        )
        for localPackage in localPackages {
            dependencies.append(contentsOf: try ManifestParser.dependencies(localPackage.manifest))
        }

        let pinsByIdentity = pinsByIdentity(resolved)
        try validateConstraints(
            dependencies, pinsByIdentity: pinsByIdentity, packageDir: packageDir, requiredBy: "Package.swift"
        )
    }

    /// Whole-graph counterpart to `validateResolvedFileSatisfiesManifest`,
    /// matching SwiftPM's `ResolverPrecomputationProvider`: it walks the pinned
    /// dependency graph (root + every reachable pinned package's own manifest)
    /// and fails when any pin can't satisfy a constraint placed on it —
    /// including transitive ones the root manifest never names directly. It
    /// reuses the checkouts a `readOnly` restore already materialized; a package
    /// whose source isn't on disk (e.g. `--print-only`, which skips restore)
    /// simply isn't recursed into, so the walk degrades to the direct check
    /// rather than failing spuriously.
    static func validateResolvedGraphSatisfiesManifests(
        packageDir: URL,
        scratchDir: URL,
        resolved: ResolvedPins,
        disableSandbox: Bool
    ) async throws {
        let pinsByIdentity = pinsByIdentity(resolved)

        let rootManifest = try await ManifestLoader.dumpPackage(
            packageDir: packageDir, disableSandbox: disableSandbox
        )
        var worklist = try ManifestParser.dependencies(rootManifest).map {
            PendingConstraint(requiredBy: "Package.swift", dependency: $0)
        }
        let localPackages = try await ManifestFileSystemDependencyGraph.collect(
            rootPackageDir: packageDir,
            rootManifest: rootManifest,
            disableSandbox: disableSandbox
        )
        for localPackage in localPackages {
            let requiredBy = "'\(localPackage.dependency.identity)'"
            worklist.append(
                contentsOf: try ManifestParser.dependencies(localPackage.manifest).map {
                    PendingConstraint(requiredBy: requiredBy, dependency: $0)
                }
            )
        }

        var expanded = Set<String>()
        while let pending = worklist.popLast() {
            let dependency = pending.dependency
            let identity = dependency.identity.lowercased()
            // Skip pins we can't confidently match (e.g. an SCM->registry
            // identity remap) to avoid a false positive; the resolver only fails
            // on pins it can prove unsatisfiable.
            guard let pin = pinsByIdentity[identity] else { continue }
            guard pinSatisfies(dependency.requirement, pin: pin) else {
                throw ToolError.message(
                    outOfDateMessage(
                        packageDir: packageDir, dependency: dependency, pin: pin, requiredBy: pending.requiredBy
                    )
                )
            }
            guard expanded.insert(identity).inserted else { continue }

            // Recurse into the pinned package's own manifest to validate its
            // transitive constraints. This needs the materialized source; if the
            // checkout/registry download is absent we can't (and don't) descend.
            let sourcePath = materializedPackagePath(scratchDir: scratchDir, pin: pin)
            guard let sourcePath,
                  try await fileSystem.exists(sourcePath.appendingPathComponent("Package.swift").absolutePath)
            else { continue }
            let manifest = try await ManifestLoader.dumpPackage(
                packageDir: sourcePath, disableSandbox: disableSandbox
            )
            let requiredBy = "'\(pin.identity)'"
            worklist.append(
                contentsOf: try ManifestParser.dependencies(manifest).map {
                    PendingConstraint(requiredBy: requiredBy, dependency: $0)
                }
            )
        }
    }

    private struct PendingConstraint {
        let requiredBy: String
        let dependency: ManifestDependency
    }

    private static func pinsByIdentity(_ resolved: ResolvedPins) -> [String: ResolvedPin] {
        var pinsByIdentity: [String: ResolvedPin] = [:]
        for pin in resolved.pins {
            pinsByIdentity[pin.identity.lowercased()] = pin
        }
        return pinsByIdentity
    }

    /// Validate a single package's direct dependency constraints against the
    /// pins. Only pins we can match by identity are checked; an unmatched
    /// dependency may be an SCM->registry identity remap rather than genuine
    /// drift, so it's skipped instead of risking a false positive that would
    /// break a working lockfile.
    private static func validateConstraints(
        _ dependencies: [ManifestDependency],
        pinsByIdentity: [String: ResolvedPin],
        packageDir: URL,
        requiredBy: String
    ) throws {
        for dependency in dependencies {
            guard let pin = pinsByIdentity[dependency.identity.lowercased()] else { continue }
            guard pinSatisfies(dependency.requirement, pin: pin) else {
                throw ToolError.message(
                    outOfDateMessage(
                        packageDir: packageDir, dependency: dependency, pin: pin, requiredBy: requiredBy
                    )
                )
            }
        }
    }

    /// Whether `pin` satisfies `requirement`, mirroring SwiftPM precomputation
    /// where each package offers only its pinned version. Version constraints
    /// are checked strictly; branch/revision are checked leniently (a missing
    /// field on the pin is treated as "no contradiction") so we never fail a
    /// lockfile on an ambiguous short/long revision or unrecorded branch.
    private static func pinSatisfies(_ requirement: Requirement, pin: ResolvedPin) -> Bool {
        switch requirement {
        case .exact, .range:
            guard let range = ManifestParser.versionRange(for: requirement) else { return true }
            // A version requirement against a branch/revision pin is genuine
            // drift (the manifest no longer asks for a versioned dependency).
            guard let versionString = pin.state.version else { return false }
            // An unparseable pin version is not proof of drift; don't fail on it.
            guard let version = try? SemVer(versionString) else { return true }
            return range.contains(version)
        case let .revision(revision):
            guard let pinned = pin.state.revision, !pinned.isEmpty, !revision.isEmpty else { return true }
            return pinned.hasPrefix(revision) || revision.hasPrefix(pinned)
        case let .branch(branch):
            guard let pinned = pin.state.branch else { return true }
            return pinned == branch
        }
    }

    /// On-disk source location a `readOnly` restore materializes a pin into,
    /// mirroring `WorkspaceRestorer`: registry downloads live under
    /// `registry/downloads/<scope>/<name>/<version>`, source-control checkouts
    /// under `checkouts/<name>`.
    private static func materializedPackagePath(scratchDir: URL, pin: ResolvedPin) -> URL? {
        if PinKind.isRegistry(pin.kind) {
            guard let subpath = try? PinKind.registryDownloadSubpath(pin) else { return nil }
            return scratchDir.appendingPathComponent("registry/downloads").appendingPathComponent(subpath)
        }
        guard PinKind.isSourceControl(pin.kind) else { return nil }
        return scratchDir.appendingPathComponent("checkouts")
            .appendingPathComponent(PinKind.checkoutDirectoryName(pin))
    }

    private static func outOfDateMessage(
        packageDir: URL,
        dependency: ManifestDependency,
        pin: ResolvedPin,
        requiredBy: String
    ) -> String {
        let resolvedPath = packageDir.appendingPathComponent("Package.resolved").path
        let pinned = pin.state.version ?? pin.state.branch ?? pin.state.revision ?? "<unknown>"
        return """
        an out-of-date Package.resolved was detected at \(resolvedPath), which is not allowed when \
        --force-resolved-versions is set: '\(dependency.identity)' is pinned to \(pinned) but \(requiredBy) \
        requires \(requirementDescription(dependency.requirement)). Update the resolved file (e.g. run \
        `tuist install` or `swift package resolve`) and commit it.
        """
    }

    private static func requirementDescription(_ requirement: Requirement) -> String {
        switch requirement {
        case let .exact(version):
            return "exactly \(version)"
        case let .range(lower, upper):
            return "\(lower)..<\(upper)"
        case let .revision(revision):
            return "revision \(revision)"
        case let .branch(branch):
            return "branch \(branch)"
        }
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
