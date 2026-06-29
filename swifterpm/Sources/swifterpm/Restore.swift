import Foundation

enum WorkspaceRestorer {
    private struct PackageContext {
        let packageRef: [String: String]
        let packagePath: URL
        let canonicalizeLocalBinaryPaths: Bool
    }

    private struct BinaryArtifact {
        let path: URL
        let kind: [String: Any]
    }

    private struct WorkspaceArtifact: @unchecked Sendable {
        let value: [String: Any]
    }

    static func restorePackage(
        scratchDir: URL,
        packageDir: URL? = nil,
        cache: Cache,
        registryConfig: RegistryConfig,
        resolved: ResolvedPins,
        progress: RestoreProgressReporter?,
        disableSandbox: Bool = false
    ) async throws {
        let scratchLock = try await PathLock.acquire(
            at: scratchDir.appendingPathComponent(".swifterpm.lock")
        )
        _ = scratchLock
        let checkouts = scratchDir.appendingPathComponent("checkouts")
        let registryDownloads = scratchDir.appendingPathComponent("registry/downloads")
        async let createCheckouts: Void = fileSystem.makeDirectory(
            at: checkouts.absolutePath, options: [.createTargetParentDirectories]
        )
        async let createRegistryDownloads: Void = fileSystem.makeDirectory(
            at: registryDownloads.absolutePath,
            options: [.createTargetParentDirectories]
        )
        _ = try await (createCheckouts, createRegistryDownloads)

        let sourcePins = resolved.pins.filter { PinKind.isSourceControl($0.kind) }
        let registryPins = resolved.pins.filter { PinKind.isRegistry($0.kind) }
        let skipped = resolved.pins.count - sourcePins.count - registryPins.count

        async let restoredSources = restoreSourcePins(
            sourcePins, checkouts: checkouts, cache: cache
        )
        async let restoredRegistry = restoreRegistryPins(
            registryPins,
            registryDownloads: registryDownloads,
            cache: cache,
            registryConfig: registryConfig
        )

        let (sourceResults, registryResults) = try await (restoredSources, restoredRegistry)

        try await restoreBinaryArtifacts(
            scratchDir: scratchDir,
            packageDir: packageDir,
            cache: cache,
            resolved: resolved,
            disableSandbox: disableSandbox,
            progress: progress
        )

        guard let progress else { return }
        for (identity, source) in sourceResults {
            progress.restoredPackage(identity: identity, path: source.path)
        }
        for (identity, source) in registryResults {
            progress.restoredPackage(identity: identity, path: source.path)
        }
        progress.restoreSummary(
            sourceCount: sourceResults.count,
            sourcePath: checkouts.path,
            registryCount: registryResults.count,
            registryPath: registryDownloads.path,
            skipped: skipped
        )
    }

    private static func restoreBinaryArtifacts(
        scratchDir: URL,
        packageDir: URL?,
        cache: Cache,
        resolved: ResolvedPins,
        disableSandbox: Bool,
        progress: RestoreProgressReporter?
    ) async throws {
        let contexts = try await packageContexts(
            packageDir: packageDir,
            scratchDir: scratchDir,
            resolved: resolved,
            disableSandbox: disableSandbox
        )
        // Dump each manifest inside the per-context fan-out so packages with
        // zero binary targets short-circuit before paying for a manifest dump,
        // and downloads for fast-dumping packages start without waiting on
        // slower ones. Per-target downloads still run concurrently within each
        // context, preserving total parallelism on multi-package restores.
        try await ConcurrentTasks.forEach(contexts) { context in
            let manifest = try await ManifestLoader.dumpPackage(
                packageDir: context.packagePath,
                disableSandbox: disableSandbox
            )
            let binaryTargets = try ManifestParser.binaryTargets(manifest)
            try await ConcurrentTasks.forEach(binaryTargets) { target in
                try await restoreBinaryArtifact(
                    target,
                    context: context,
                    scratchDir: scratchDir,
                    cache: cache,
                    progress: progress
                )
            }
        }
    }

    private static func restoreBinaryArtifact(
        _ target: ManifestBinaryTarget,
        context: PackageContext,
        scratchDir: URL,
        cache: Cache,
        progress: RestoreProgressReporter?
    ) async throws {
        switch target.source {
        case let .remote(url, checksum):
            let identity = context.packageRef["identity"] ?? target.name
            let cachedArtifact = cache.binaryArtifactDirectory(
                identity: identity,
                targetName: target.name,
                checksum: checksum
            )
            if try await binaryArtifact(in: cachedArtifact) == nil {
                let lock = try await cache.lock(namespace: "artifacts", key: cachedArtifact.path)
                _ = lock
                if try await binaryArtifact(in: cachedArtifact) == nil {
                    try await downloadBinaryArtifact(
                        identity: identity,
                        targetName: target.name,
                        url: url,
                        checksum: checksum,
                        cache: cache,
                        destination: cachedArtifact,
                        progress: progress
                    )
                }
            }

            let scratchArtifact = artifactDirectory(
                scratchDir: scratchDir,
                packageIdentity: identity,
                targetName: target.name
            )
            try await replaceScratchArtifact(
                source: cachedArtifact,
                destination: scratchArtifact
            )

            progress?.restoredBinaryArtifact(
                identity: identity, target: target.name, path: cachedArtifact.path
            )
        case let .local(path):
            let artifactPath = binaryTargetPath(
                path,
                packagePath: context.packagePath,
                canonicalize: context.canonicalizeLocalBinaryPaths
            )
            guard artifactPath.pathExtension.lowercased() == "zip" else { return }
            let identity = context.packageRef["identity"] ?? target.name
            let checksum = try Hashing.sha256Hex(fileAt: artifactPath)
            let cachedArtifact = cache.binaryArtifactDirectory(
                identity: identity,
                targetName: target.name,
                checksum: checksum
            )
            if try await binaryArtifact(in: cachedArtifact) == nil {
                try await extractBinaryArtifactArchive(
                    archivePath: artifactPath,
                    destination: cachedArtifact
                )
            }
            let scratchArtifact = artifactDirectory(
                scratchDir: scratchDir,
                packageIdentity: identity,
                targetName: target.name
            )
            try await replaceScratchArtifact(
                source: cachedArtifact,
                destination: scratchArtifact
            )
            progress?.restoredBinaryArtifact(
                identity: identity, target: target.name, path: cachedArtifact.path
            )
        }
    }

    private static func replaceScratchArtifact(source: URL, destination: URL) async throws {
        let lock = try await PathLock.acquire(
            at: destination.deletingLastPathComponent()
                .appendingPathComponent(".\(destination.lastPathComponent).lock")
        )
        defer { _ = lock }
        try await fileSystem.replaceWithSymlinkedDirectory(
            source: source,
            destination: destination
        )
    }

    private static func downloadBinaryArtifact(
        identity: String,
        targetName: String,
        url: String,
        checksum: String,
        cache: Cache,
        destination: URL,
        progress: RestoreProgressReporter?
    ) async throws {
        let archivePath = cache.binaryArtifactArchivePath(
            url: url,
            checksum: checksum
        )
        // A valid cached archive has already been hashed and verified by
        // `validCachedBinaryArtifactArchive`, so extract it directly. Only a
        // freshly downloaded archive needs the (single) verification hash;
        // re-hashing a known-good multi-hundred-MB archive is pure waste.
        if try await !validCachedBinaryArtifactArchive(
            archivePath,
            expectedChecksum: checksum
        ) {
            let lock = try await cache.lock(namespace: "artifact-archives", key: archivePath.path)
            defer { _ = lock }
            if try await !validCachedBinaryArtifactArchive(
                archivePath,
                expectedChecksum: checksum
            ) {
                try? await fileSystem.removePath(archivePath)
                let remoteURL = try artifactURL(url)
                progress?.downloadingBinaryArtifact(identity: identity, target: targetName)
                try await HTTPClient.download(
                    url: remoteURL,
                    destination: archivePath,
                    headers: await HTTPClient.binaryArtifactHeaders(for: remoteURL)
                )

                let actualChecksum = try Hashing.sha256Hex(fileAt: archivePath)
                guard actualChecksum.caseInsensitiveCompare(checksum) == .orderedSame else {
                    try? await fileSystem.removePath(archivePath)
                    throw ToolError.message(
                        "\(targetName) checksum mismatch: expected \(checksum), got \(actualChecksum)"
                    )
                }
            }
        }

        try await extractBinaryArtifactArchive(
            archivePath: archivePath,
            destination: destination
        )
    }

    private static func validCachedBinaryArtifactArchive(
        _ archivePath: URL,
        expectedChecksum: String
    ) async throws -> Bool {
        guard try await fileSystem.exists(archivePath.absolutePath) else {
            return false
        }
        let actualChecksum = try Hashing.sha256Hex(fileAt: archivePath)
        if actualChecksum.caseInsensitiveCompare(expectedChecksum) == .orderedSame {
            return true
        }
        try? await fileSystem.removePath(archivePath)
        return false
    }

    private static func extractBinaryArtifactArchive(
        archivePath: URL,
        destination: URL
    ) async throws {
        try await fileSystem.makeDirectory(
            at: destination.deletingLastPathComponent().absolutePath,
            options: [.createTargetParentDirectories]
        )
        let lock = try await PathLock.acquire(
            at: destination.deletingLastPathComponent()
                .appendingPathComponent(".\(destination.lastPathComponent).lock")
        )
        defer { _ = lock }
        if try await binaryArtifact(in: destination) != nil {
            return
        }

        let temp = try await fileSystem.temporaryDirectory(
            in: destination.deletingLastPathComponent()
        )

        do {
            try await SystemProcess.run(
                "/usr/bin/unzip",
                ["-q", archivePath.path, "-d", temp.path]
            )
            // Strip the macOS resource-fork sidecar that Finder-zipped archives carry. It
            // contains a shadow copy of each bundle (no Info.plist) which downstream scanners
            // would otherwise pick up and reject as a malformed xcframework.
            try await removeResourceForkDirectories(in: temp)
            if try await shouldStripFirstLevel(
                archiveDirectory: temp,
                acceptableExtensions: ["artifactbundle", "xcframework"]
            ) {
                try await fileSystem.flattenSingleDirectory(temp)
            }
            guard try await binaryArtifact(in: temp) != nil else {
                throw ToolError.message("\(archivePath.lastPathComponent) has no binary artifact")
            }

            if try await fileSystem.exists(destination.absolutePath) {
                try await fileSystem.removePath(destination)
            }
            try await fileSystem.makeDirectory(
                at: destination.deletingLastPathComponent().absolutePath,
                options: [.createTargetParentDirectories]
            )
            try await fileSystem.makeDirectory(
                at: destination.absolutePath,
                options: [.createTargetParentDirectories]
            )
            let entries = try await fileSystem.contentsOfDirectory(at: temp)
            for entry in entries {
                try await fileSystem.move(
                    from: entry.absolutePath,
                    to: destination.appendingPathComponent(entry.lastPathComponent).absolutePath,
                    options: []
                )
            }
            try? await fileSystem.removePath(temp)
        } catch {
            try? await fileSystem.removePath(temp)
            throw error
        }
    }

    private static func artifactURL(_ value: String) throws -> URL {
        guard let url = URL(string: value) else {
            throw ToolError.message("invalid binary artifact URL: \(value)")
        }
        return url
    }

    private static func packageContexts(
        packageDir: URL?,
        scratchDir: URL,
        resolved: ResolvedPins,
        disableSandbox: Bool
    ) async throws -> [PackageContext] {
        var contexts: [PackageContext] = []

        if let packageDir {
            contexts.append(
                PackageContext(
                    packageRef: rootPackageRef(packageDir),
                    packagePath: packageDir,
                    canonicalizeLocalBinaryPaths: true
                )
            )
            let manifest = try await ManifestLoader.dumpPackage(
                packageDir: packageDir,
                disableSandbox: disableSandbox
            )
            for localPackage in try await ManifestFileSystemDependencyGraph.collect(
                rootPackageDir: packageDir,
                rootManifest: manifest,
                disableSandbox: disableSandbox
            ) {
                contexts.append(
                    PackageContext(
                        packageRef: fileSystemPackageRef(
                            localPackage.dependency,
                            packagePath: localPackage.packagePath,
                            name: ManifestParser.packageName(localPackage.manifest)
                        ),
                        packagePath: localPackage.packagePath,
                        canonicalizeLocalBinaryPaths: true
                    )
                )
            }
        }

        for pin in resolved.pins {
            guard PinKind.isSourceControl(pin.kind) || PinKind.isRegistry(pin.kind) else {
                continue
            }
            let packagePath = try packagePathForPin(scratchDir: scratchDir, pin: pin)
            contexts.append(
                PackageContext(
                    packageRef: try await packageRef(
                        pin,
                        packagePath: packagePath,
                        disableSandbox: disableSandbox
                    ),
                    packagePath: packagePath,
                    canonicalizeLocalBinaryPaths: false
                )
            )
        }

        return contexts
    }

    private static func rootPackageRef(_ packageDir: URL) -> [String: String] {
        let canonical = PathCanonicalizer.realpath(packageDir)
        return [
            "identity": canonical.lastPathComponent.lowercased(),
            "kind": "root",
            "location": canonical.path,
            "name": canonical.lastPathComponent,
        ]
    }

    private static func fileSystemPackageRef(
        _ dependency: ManifestFileSystemDependency,
        packagePath: URL,
        name: String? = nil
    )
        -> [String: String]
    {
        [
            "identity": dependency.identity,
            "kind": "fileSystem",
            "location": packagePath.path,
            "name": name ?? dependency.name,
        ]
    }

    private static func packageRef(_ pin: ResolvedPin) throws -> [String: String] {
        if PinKind.isRegistry(pin.kind) {
            return [
                "identity": pin.identity,
                "kind": "registry",
                "location": pin.identity,
                "name": pin.identity,
            ]
        }
        return [
            "identity": pin.identity,
            "kind": pin.kind,
            "location": pin.location,
            "name": PinKind.checkoutDirectoryName(pin),
        ]
    }

    private static func packageRef(
        _ pin: ResolvedPin,
        packagePath: URL,
        disableSandbox: Bool
    ) async throws -> [String: String] {
        var ref = try packageRef(pin)
        guard PinKind.isSourceControl(pin.kind) else {
            return ref
        }
        let manifestPath = packagePath.appendingPathComponent("Package.swift")
        guard try await fileSystem.exists(manifestPath.absolutePath) else {
            return ref
        }

        let manifest = try await ManifestLoader.dumpPackage(
            packageDir: packagePath,
            disableSandbox: disableSandbox
        )
        if let name = ManifestParser.packageName(manifest) {
            ref["name"] = name
        }
        return ref
    }

    private static func artifactDirectory(
        scratchDir: URL,
        packageIdentity: String,
        targetName: String
    ) -> URL {
        scratchDir
            .appendingPathComponent("artifacts")
            .appendingPathComponent(SafePathComponent.make(packageIdentity))
            .appendingPathComponent(SafePathComponent.make(targetName))
    }

    private static func binaryTargetPath(
        _ path: String,
        packagePath: URL,
        canonicalize: Bool
    ) -> URL {
        let artifactPath: URL
        if path.hasPrefix("/") {
            artifactPath = URL(fileURLWithPath: path)
        } else {
            artifactPath = packagePath
                .appendingPathComponent(path)
                .standardizedFileURL
        }
        return canonicalize ? PathCanonicalizer.realpath(artifactPath) : artifactPath
    }

    private static func packagePathForPin(scratchDir: URL, pin: ResolvedPin) throws -> URL {
        if PinKind.isRegistry(pin.kind) {
            return try scratchDir
                .appendingPathComponent("registry/downloads")
                .appendingPathComponent(PinKind.registryDownloadSubpath(pin))
        }
        return scratchDir
            .appendingPathComponent("checkouts")
            .appendingPathComponent(PinKind.checkoutDirectoryName(pin))
    }

    private static func binaryArtifact(in directory: URL) async throws -> BinaryArtifact? {
        let artifacts = try await binaryArtifacts(in: directory)
        return artifacts.last
    }

    private static func binaryArtifacts(in directory: URL) async throws -> [BinaryArtifact] {
        guard try await fileSystem.exists(directory.absolutePath) else { return [] }
        if fileSystem.isDirectoryAndNotSymlink(directory) {
            if directory.pathExtension == "xcframework" {
                return [BinaryArtifact(path: directory, kind: ["xcframework": [:]])]
            }
            if directory.pathExtension == "artifactbundle" {
                return [BinaryArtifact(path: directory, kind: ["artifactsArchive": [:]])]
            }
        }
        var result: [BinaryArtifact] = []
        let entries = try await fileSystem.contentsOfDirectory(at: directory)
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            guard fileSystem.isDirectoryAndNotSymlink(entry) else { continue }
            if entry.lastPathComponent == "__MACOSX" { continue }
            if entry.pathExtension == "xcframework" {
                result.append(BinaryArtifact(path: entry, kind: ["xcframework": [:]]))
            } else if entry.pathExtension == "artifactbundle" {
                result.append(BinaryArtifact(path: entry, kind: ["artifactsArchive": [:]]))
            } else {
                let nestedArtifacts = try await binaryArtifacts(in: entry)
                result.append(contentsOf: nestedArtifacts)
            }
        }
        return result
    }

    private static func removeResourceForkDirectories(in directory: URL) async throws {
        let entries = try await fileSystem.contentsOfDirectory(at: directory)
        for entry in entries where entry.lastPathComponent == "__MACOSX" {
            try await fileSystem.removePath(entry)
        }
    }

    private static func shouldStripFirstLevel(
        archiveDirectory: URL,
        acceptableExtensions: Set<String>
    ) async throws -> Bool {
        var subdirectories: [URL] = []
        for entry in try await fileSystem.contentsOfDirectory(at: archiveDirectory) {
            if fileSystem.isDirectoryAndNotSymlink(entry) {
                subdirectories.append(entry)
            }
        }
        guard subdirectories.count == 1, let rootDirectory = subdirectories.first else {
            return false
        }
        if acceptableExtensions.contains(rootDirectory.pathExtension.lowercased()) {
            return false
        }
        for entry in try await fileSystem.contentsOfDirectory(at: rootDirectory) {
            if acceptableExtensions.contains(entry.pathExtension.lowercased()) {
                return true
            }
        }
        return false
    }

    private static func restoreSourcePins(
        _ pins: [ResolvedPin],
        checkouts: URL,
        cache: Cache
    ) async throws -> [(String, URL)] {
        let results = try await ConcurrentTasks.map(pins) { pin in
            do {
                let source = try await ensureSource(cache: cache, pin: pin)
                let checkout = checkouts.appendingPathComponent(PinKind.checkoutDirectoryName(pin))
                try await fileSystem.replaceWithSymlinkedDirectory(
                    source: source, destination: checkout
                )
                return (pin.identity, source)
            } catch {
                throw sourceRestoreError(pin: pin, error: error)
            }
        }
        return results.sorted { $0.0 < $1.0 }
    }

    private static func sourceRestoreError(pin: ResolvedPin, error: any Error) -> ToolError {
        let revision = (try? pin.revision()).map { " at \($0)" } ?? ""
        return ToolError.message(
            "failed to restore \(pin.identity) from \(pin.location)\(revision): \(error)"
        )
    }

    private static func restoreRegistryPins(
        _ pins: [ResolvedPin],
        registryDownloads: URL,
        cache: Cache,
        registryConfig: RegistryConfig
    ) async throws -> [(String, URL)] {
        let results = try await ConcurrentTasks.map(pins) { pin in
            let source = try await ensureRegistrySource(
                cache: cache, registryConfig: registryConfig, pin: pin
            )
            let download = try registryDownloads.appendingPathComponent(
                PinKind.registryDownloadSubpath(pin)
            )
            try await fileSystem.replaceWithSymlinkedDirectory(
                source: source, destination: download
            )
            return (pin.identity, source)
        }
        return results.sorted { $0.0 < $1.0 }
    }

    static func ensureSource(cache: Cache, pin: ResolvedPin) async throws -> URL {
        let destination = try cache.sourcePath(pin: pin)
        if try await cachedSourceIsUsable(destination) {
            return destination
        }

        let lock = try await cache.lock(namespace: "sources", key: destination.path)
        _ = lock
        if try await cachedSourceIsUsable(destination) {
            return destination
        }
        if try await fileSystem.exists(destination.absolutePath) {
            try await fileSystem.remove(destination.absolutePath)
        }
        let parent = destination.deletingLastPathComponent()
        try await fileSystem.makeDirectory(at: parent.absolutePath, options: [.createTargetParentDirectories])
        let temp = try await fileSystem.temporaryDirectory(in: parent)

        do {
            do {
                try await downloadSourceArchive(cache: cache, pin: pin, destination: temp)
            } catch {
                try await resetDirectory(temp)
                try await shallowFetchCheckout(pin: pin, destination: temp)
            }

            do {
                try await fileSystem.move(from: temp.absolutePath, to: destination.absolutePath, options: [])
            } catch {
                if try await cachedSourceIsUsable(destination) {
                    try? await fileSystem.remove(temp.absolutePath)
                    return destination
                }
                throw error
            }
        } catch {
            try? await fileSystem.remove(temp.absolutePath)
            throw error
        }
        return destination
    }

    private static func cachedSourceIsUsable(_ source: URL) async throws -> Bool {
        guard try await fileSystem.exists(
            source.appendingPathComponent("Package.swift").absolutePath
        ) else {
            return false
        }
        return try await submodulesAreMaterialized(in: source)
    }

    private static func submodulesAreMaterialized(in source: URL) async throws -> Bool {
        for path in try await submodulePaths(in: source) {
            let submodule = source.appendingPathComponent(path)
            guard fileSystem.isDirectoryAndNotSymlink(submodule) else {
                return false
            }
            let entries = try await fileSystem.contentsOfDirectory(at: submodule)
            if entries.allSatisfy({ $0.lastPathComponent == ".git" }) {
                return false
            }
        }
        return true
    }

    static func ensureRegistrySource(cache: Cache, registryConfig: RegistryConfig, pin: ResolvedPin)
        async throws -> URL
    {
        let version = try pin.versionString()
        let archive = try await RegistryClient.sourceArchive(
            registryConfig: registryConfig,
            identity: pin.identity,
            version: version
        )
        let destination = cache.registrySourcePath(
            identity: pin.identity,
            version: version,
            registryURL: archive.registryURL.absoluteString,
            checksum: archive.checksum
        )
        let manifest = destination.appendingPathComponent("Package.swift")
        if try await fileSystem.exists(manifest.absolutePath) {
            return destination
        }

        let lock = try await cache.lock(namespace: "sources", key: destination.path)
        _ = lock
        if try await fileSystem.exists(manifest.absolutePath) {
            return destination
        }
        if try await fileSystem.exists(destination.absolutePath) {
            try await fileSystem.remove(destination.absolutePath)
        }
        let parent = destination.deletingLastPathComponent()
        try await fileSystem.makeDirectory(at: parent.absolutePath, options: [.createTargetParentDirectories])
        let temp = try await fileSystem.temporaryDirectory(in: parent)

        do {
            try await RegistryClient.downloadArchive(
                cache: cache,
                registryConfig: registryConfig,
                registryURL: archive.registryURL,
                identity: pin.identity,
                version: version,
                expectedChecksum: archive.checksum,
                destination: temp
            )

            try await fileSystem.move(from: temp.absolutePath, to: destination.absolutePath, options: [])
        } catch {
            try? await fileSystem.remove(temp.absolutePath)
            if try await fileSystem.exists(manifest.absolutePath) {
                return destination
            }
            throw error
        }
        return destination
    }

    private static func downloadSourceArchive(cache: Cache, pin: ResolvedPin, destination: URL)
        async throws
    {
        if (try? GitHubRepo(location: pin.location)) != nil, await GitHubAuth.hasSession() {
            try await downloadGitHubArchive(cache: cache, pin: pin, destination: destination)
            return
        }
        if let repo = try? GitLabRepo(location: pin.location),
           await GitLabAuth.hasSession(host: repo.host)
        {
            try await downloadGitLabArchive(cache: cache, pin: pin, destination: destination)
            return
        }
        throw ToolError.message(
            "no authenticated source archive endpoint available for \(pin.location)"
        )
    }

    private static func downloadGitHubArchive(cache: Cache, pin: ResolvedPin, destination: URL)
        async throws
    {
        let repo = try GitHubRepo(location: pin.location)
        let revision = try pin.revision()
        let archivePath = cache.archivePath(url: pin.location, revision: revision)
        if try !(await fileSystem.exists(archivePath.absolutePath)) {
            let lock = try await cache.lock(namespace: "archives", key: archivePath.path)
            _ = lock
            if try !(await fileSystem.exists(archivePath.absolutePath)) {
                var headers = ["User-Agent": "swifterpm/0.1"]
                if let token = await GitHubAuth.token() {
                    headers["Authorization"] = "Bearer \(token)"
                }
                let url = URL(
                    string:
                    "https://api.github.com/repos/\(repo.owner)/\(repo.repo)/tarball/\(revision)"
                )!
                try await HTTPClient.download(url: url, destination: archivePath, headers: headers)
            }
        }

        try await SystemProcess.run(
            "/usr/bin/tar", ["-xzf", archivePath.path, "-C", destination.path]
        )
        try await fileSystem.flattenSingleDirectory(destination)
        try await rejectArchiveWithSubmodules(destination)
    }

    private static func downloadGitLabArchive(cache: Cache, pin: ResolvedPin, destination: URL)
        async throws
    {
        let repo = try GitLabRepo(location: pin.location)
        let revision = try pin.revision()
        let archivePath = cache.archivePath(url: pin.location, revision: revision)
        if try !(await fileSystem.exists(archivePath.absolutePath)) {
            let lock = try await cache.lock(namespace: "archives", key: archivePath.path)
            _ = lock
            if try !(await fileSystem.exists(archivePath.absolutePath)) {
                try await GitLabAPI.downloadArchive(
                    repo: repo, revision: revision, destination: archivePath
                )
            }
        }

        try await SystemProcess.run(
            "/usr/bin/tar", ["-xzf", archivePath.path, "-C", destination.path]
        )
        try await fileSystem.flattenSingleDirectory(destination)
        try await rejectArchiveWithSubmodules(destination)
    }

    private static func shallowFetchCheckout(pin: ResolvedPin, destination: URL) async throws {
        let revision = try pin.revision()
        let isLocalSourceControlPackage =
            try await PackageResolver.localSourceControlPackageLocation(pin.location) != nil
        var attempts: [(candidate: String, error: any Error)] = []
        for location in SourceControlLocations.fetchCandidates(pin.location) {
            do {
                try await resetDirectory(destination)
                try await SystemProcess.run("/usr/bin/git", ["init", destination.path])
                try await SystemProcess.run(
                    "/usr/bin/git", ["-C", destination.path, "remote", "add", "origin", location]
                )
                let authArguments = await GitTransportAuth.configArguments(for: location)
                try await SystemProcess.run(
                    "/usr/bin/git",
                    authArguments
                        + ["-C", destination.path, "fetch", "--depth=1", "origin", revision],
                    environment: SystemProcess.nonInteractiveGitEnvironment
                )
                try await SystemProcess.run(
                    "/usr/bin/git", ["-C", destination.path, "checkout", "--detach", "FETCH_HEAD"]
                )
                try await updateSubmodulesIfNeeded(
                    in: destination,
                    gitConfigArguments: authArguments,
                    allowFileProtocol: isLocalSourceControlPackage
                )
                let gitDir = destination.appendingPathComponent(".git")
                if !isLocalSourceControlPackage,
                   try await fileSystem.exists(gitDir.absolutePath)
                {
                    try await fileSystem.remove(gitDir.absolutePath)
                }
                return
            } catch {
                attempts.append((location, error))
            }
        }
        throw GitFetchFailure.error(location: pin.location, attempts: attempts)
    }

    private static func updateSubmodulesIfNeeded(
        in destination: URL,
        gitConfigArguments: [String],
        allowFileProtocol: Bool
    ) async throws {
        guard try await !submodulePaths(in: destination).isEmpty else {
            return
        }
        var arguments = ["-C", destination.path] + gitConfigArguments
        if allowFileProtocol {
            arguments.append(contentsOf: ["-c", "protocol.file.allow=always"])
        }
        arguments.append(contentsOf: ["submodule", "update", "--init", "--recursive"])
        try await SystemProcess.run(
            "/usr/bin/git",
            arguments,
            environment: SystemProcess.nonInteractiveGitEnvironment
        )
    }

    private static func submodulePaths(in source: URL) async throws -> [String] {
        let gitmodules = source.appendingPathComponent(".gitmodules")
        guard try await fileSystem.exists(gitmodules.absolutePath) else {
            return []
        }

        let output: String
        do {
            output = try await SystemProcess.output(
                "/usr/bin/git",
                ["config", "-f", gitmodules.path, "--get-regexp", #"submodule\..*\.path"#]
            )
        } catch {
            return []
        }

        return output.split(separator: "\n").compactMap { line in
            guard let separatorIndex = line.firstIndex(where: { $0.isWhitespace }) else {
                return nil
            }
            let path = String(line[line.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        }
    }

    private static func rejectArchiveWithSubmodules(_ destination: URL) async throws {
        if try await fileSystem.exists(destination.appendingPathComponent(".gitmodules").absolutePath) {
            throw ToolError.message(
                "\(destination.path) declares git submodules, which GitHub source archives do not include"
            )
        }
    }

    private static func resetDirectory(_ url: URL) async throws {
        if try await fileSystem.exists(url.absolutePath) {
            let entries = try await fileSystem.contentsOfDirectory(at: url)
            try await ConcurrentTasks.forEach(entries) { entry in
                try await fileSystem.removePath(entry)
            }
        }
        try await fileSystem.makeDirectory(at: url.absolutePath, options: [.createTargetParentDirectories])
    }

    static func writeWorkspaceState(
        packageDir: URL, scratchDir: URL, resolved: ResolvedPins, disableSandbox: Bool
    ) async throws {
        var dependencies: [[String: Any]] = []

        for pin in resolved.pins {
            if PinKind.isSourceControl(pin.kind) {
                var checkoutState: [String: Any] = try ["revision": pin.revision()]
                if let branch = pin.state.branch { checkoutState["branch"] = branch }
                if let version = pin.state.version { checkoutState["version"] = version }
                let ref = try await packageRef(
                    pin,
                    packagePath: packagePathForPin(scratchDir: scratchDir, pin: pin),
                    disableSandbox: disableSandbox
                )
                dependencies.append([
                    "basedOn": NSNull(),
                    "packageRef": ref,
                    "state": [
                        "checkoutState": checkoutState,
                        "name": "sourceControlCheckout",
                    ],
                    "subpath": PinKind.checkoutDirectoryName(pin),
                ])
            } else if PinKind.isRegistry(pin.kind) {
                let ref = try packageRef(pin)
                try dependencies.append([
                    "basedOn": NSNull(),
                    "packageRef": ref,
                    "state": [
                        "name": "registryDownload",
                        "version": pin.versionString(),
                    ],
                    "subpath": PinKind.registryDownloadSubpath(pin),
                ])
            }
        }

        let manifest = try await ManifestLoader.dumpPackage(
            packageDir: packageDir, disableSandbox: disableSandbox
        )
        for localPackage in try await ManifestFileSystemDependencyGraph.collect(
            rootPackageDir: packageDir,
            rootManifest: manifest,
            disableSandbox: disableSandbox
        ) {
            let ref = fileSystemPackageRef(
                localPackage.dependency,
                packagePath: localPackage.packagePath,
                name: ManifestParser.packageName(localPackage.manifest)
            )
            dependencies.append([
                "basedOn": NSNull(),
                "packageRef": ref,
                "state": [
                    "name": "fileSystem",
                    "path": localPackage.packagePath.path,
                ],
                "subpath": localPackage.dependency.identity,
            ])
        }
        dependencies.sort { jsonPackageIdentity($0) < jsonPackageIdentity($1) }

        var artifacts = try await workspaceArtifacts(
            packageDir: packageDir,
            scratchDir: scratchDir,
            resolved: resolved,
            disableSandbox: disableSandbox
        )
        artifacts.sort {
            let lhs = "\(jsonPackageIdentity($0))|\($0["targetName"] as? String ?? "")"
            let rhs = "\(jsonPackageIdentity($1))|\($1["targetName"] as? String ?? "")"
            return lhs < rhs
        }

        let state: [String: Any] = [
            "object": [
                "artifacts": artifacts,
                "dependencies": dependencies,
                "prebuilts": try await existingWorkspacePrebuilts(scratchDir: scratchDir),
            ],
            "version": 7,
        ]
        try await fileSystem.makeDirectory(at: scratchDir.absolutePath, options: [.createTargetParentDirectories])
        try await fileSystem.atomicWrite(
            JSONFormatter.prettyData(state),
            to: scratchDir.appendingPathComponent("workspace-state.json")
        )
    }

    private static func existingWorkspacePrebuilts(scratchDir: URL) async throws -> [[String: Any]] {
        let statePath = scratchDir.appendingPathComponent("workspace-state.json")
        guard try await fileSystem.exists(statePath.absolutePath) else { return [] }

        let state = try JSONSerialization.jsonObject(
            with: await fileSystem.readFile(at: statePath.absolutePath)
        ) as? [String: Any]
        let object = state?["object"] as? [String: Any]

        return (object?["prebuilts"] as? [[String: Any]])?.map(sanitizeWorkspacePrebuilt) ?? []
    }

    private static func sanitizeWorkspacePrebuilt(_ prebuilt: [String: Any]) -> [String: Any] {
        var sanitized = prebuilt
        if let path = prebuilt["path"] as? String {
            sanitized["path"] = sanitizedWorkspaceStatePath(path)
        }
        if let checkoutPath = prebuilt["checkoutPath"] as? String {
            sanitized["checkoutPath"] = sanitizedWorkspaceStatePath(checkoutPath)
        }
        if let includePath = prebuilt["includePath"] as? [String] {
            sanitized["includePath"] = includePath.map(sanitizedWorkspaceStatePath)
        }
        return sanitized
    }

    private static func sanitizedWorkspaceStatePath(_ path: String) -> String {
        String(path.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
    }

    private static func workspaceArtifacts(
        packageDir: URL,
        scratchDir: URL,
        resolved: ResolvedPins,
        disableSandbox: Bool
    ) async throws -> [[String: Any]] {
        let contexts = try await packageContexts(
            packageDir: packageDir,
            scratchDir: scratchDir,
            resolved: resolved,
            disableSandbox: disableSandbox
        )
        let artifactGroups = try await ConcurrentTasks.map(contexts) { context -> [WorkspaceArtifact] in
            guard try await fileSystem.exists(
                context.packagePath.appendingPathComponent("Package.swift").absolutePath
            ) else { return [] }

            let manifest = try await ManifestLoader.dumpPackage(
                packageDir: context.packagePath,
                disableSandbox: disableSandbox
            )
            let targetArtifacts = try await ConcurrentTasks.map(
                try ManifestParser.binaryTargets(manifest)
            ) { target in
                try await workspaceArtifact(
                    target,
                    context: context,
                    scratchDir: scratchDir
                )
            }
            return targetArtifacts.compactMap { $0 }
        }
        return artifactGroups.flatMap { $0 }.map(\.value)
    }

    private static func workspaceArtifact(
        _ target: ManifestBinaryTarget,
        context: PackageContext,
        scratchDir: URL
    ) async throws -> WorkspaceArtifact? {
        let identity = context.packageRef["identity"] ?? target.name
        let artifact: BinaryArtifact
        let source: [String: Any]

        switch target.source {
        case let .remote(url, checksum):
            let directory = artifactDirectory(
                scratchDir: scratchDir,
                packageIdentity: identity,
                targetName: target.name
            )
            guard let restored = try await binaryArtifact(in: directory) else {
                throw ToolError.message("\(target.name) binary artifact has not been restored")
            }
            artifact = restored
            source = [
                "checksum": checksum,
                "type": "remote",
                "url": url,
            ]
        case let .local(path):
            let localPath = binaryTargetPath(
                path,
                packagePath: context.packagePath,
                canonicalize: context.canonicalizeLocalBinaryPaths
            )
            if localPath.pathExtension.lowercased() == "zip" {
                let directory = artifactDirectory(
                    scratchDir: scratchDir,
                    packageIdentity: identity,
                    targetName: target.name
                )
                guard let restored = try await binaryArtifact(in: directory) else {
                    throw ToolError.message("\(target.name) local binary archive has not been extracted")
                }
                artifact = restored
                source = try [
                    "checksum": Hashing.sha256Hex(fileAt: localPath),
                    "type": "local",
                ]
            } else {
                guard let local = try await binaryArtifact(in: localPath) else {
                    return nil
                }
                artifact = local
                source = ["type": "local"]
            }
        }

        return WorkspaceArtifact(
            value: [
                "kind": artifact.kind,
                "packageRef": context.packageRef,
                "path": artifact.path.path,
                "source": source,
                "targetName": target.name,
            ]
        )
    }

    private static func jsonPackageIdentity(_ object: [String: Any]) -> String {
        guard let packageRef = object["packageRef"] as? [String: Any],
              let identity = packageRef["identity"] as? String
        else {
            return ""
        }
        return identity
    }
}
