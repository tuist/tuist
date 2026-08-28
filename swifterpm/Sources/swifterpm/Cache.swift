import Foundation

struct Cache: Sendable {
    let root: URL

    init(root: URL?) async throws {
        self.root = try Cache.resolvedRoot(root)
        let cacheRoot = self.root
        let topLevelPaths = [
            "sources",
            "archives",
            "registry",
            "metadata",
            "locks",
            "virtual",
            "artifacts",
        ]
        try await ConcurrentTasks.forEach(topLevelPaths) { path in
            try await fileSystem.makeDirectory(
                at: cacheRoot.appendingPathComponent(path).absolutePath,
                options: [.createTargetParentDirectories]
            )
        }
        try await ConcurrentTasks.forEach([
            "registry/archives",
            "metadata/remotes",
            "virtual/checkouts",
        ]) { path in
            try await fileSystem.makeDirectory(
                at: cacheRoot.appendingPathComponent(path).absolutePath
            )
        }
    }

    func sourcePath(pin: ResolvedPin) throws -> URL {
        try Cache.sourcePath(root: root, pin: pin)
    }

    static func sourcePath(root: URL, pin: ResolvedPin) throws -> URL {
        if pin.kind == "registry" {
            throw ToolError.message("registry source paths require registry URL and checksum")
        }
        let version = pin.state.version ?? pin.state.branch ?? "revision"
        return
            try root
                .appendingPathComponent("sources")
                .appendingPathComponent(SafePathComponent.make(pin.identity))
                .appendingPathComponent(
                    SafePathComponent.make("\(version)-\(Hashing.shortRevision(pin.revision()))"))
    }

    func archivePath(url: String, revision: String) -> URL {
        root
            .appendingPathComponent("archives")
            .appendingPathComponent(
                "\(Hashing.stable(url))-\(Hashing.shortRevision(revision)).tar.gz")
    }

    func registrySourcePath(
        identity: String,
        version: String,
        registryURL: String,
        checksum: String
    ) -> URL {
        root
            .appendingPathComponent("sources")
            .appendingPathComponent(SafePathComponent.make(identity))
            .appendingPathComponent(
                SafePathComponent.make([
                    version,
                    String(Hashing.stable(registryURL).prefix(12)),
                    checksum,
                    "registry",
                ].joined(separator: "-"))
            )
    }

    func registryArchivePath(
        identity: String,
        version: String,
        registryURL: String,
        checksum: String
    ) -> URL {
        root
            .appendingPathComponent("registry/archives")
            .appendingPathComponent(
                SafePathComponent.make([
                    Hashing.stable(identity),
                    version,
                    String(Hashing.stable(registryURL).prefix(12)),
                    checksum,
                ].joined(separator: "-") + ".zip")
            )
    }

    func binaryArtifactArchivePath(url: String, checksum: String) -> URL {
        root
            .appendingPathComponent("archives")
            .appendingPathComponent(
                "artifact-\(Hashing.stable(url))-\(String(checksum.prefix(12))).zip")
    }

    func binaryArtifactDirectory(identity: String, targetName: String, checksum: String) -> URL {
        root
            .appendingPathComponent("artifacts")
            .appendingPathComponent(SafePathComponent.make(identity))
            .appendingPathComponent(
                SafePathComponent.make("\(targetName)-\(String(checksum.prefix(12)))"))
    }

    func remoteVersionsPath(location: String) -> URL {
        root
            .appendingPathComponent("metadata/remotes")
            .appendingPathComponent("\(Hashing.stable(location)).json")
    }

    func lock(namespace: String, key: String) async throws -> PathLock {
        try await PathLock.acquire(
            at: root.appendingPathComponent("locks").appendingPathComponent(namespace)
                .appendingPathComponent("\(Hashing.stable(key)).lock")
        )
    }

    func hasCachedSources() async throws -> Bool {
        try await Cache.hasCachedSources(at: root)
    }

    static func resolvedRoot(_ root: URL?) throws -> URL {
        try root ?? defaultRoot()
    }

    static func hasCachedSources(at root: URL) async throws -> Bool {
        let sources = root.appendingPathComponent("sources")
        guard try await fileSystem.exists(sources.absolutePath) else {
            return false
        }
        return try await !fileSystem.contentsOfDirectory(at: sources).isEmpty
    }

    private static func defaultRoot() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        if let xdg = env["XDG_CACHE_HOME"], xdg.hasPrefix("/") {
            return URL(fileURLWithPath: xdg).appendingPathComponent("swifterpm")
        }
        if let home = env["HOME"], home.hasPrefix("/") {
            return URL(fileURLWithPath: home).appendingPathComponent(".cache/swifterpm")
        }
        throw ToolError.message("could not find user cache directory from XDG_CACHE_HOME or HOME")
    }
}
