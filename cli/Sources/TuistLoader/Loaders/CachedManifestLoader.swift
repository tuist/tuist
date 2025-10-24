import _NIOFileSystem
import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

/// Cached Manifest Loader
///
/// A manifest loader that caches json representations of the manifests it loads to disk (`~/.tuist/Cache/Manifests`)
/// along with their hashes. This allows speeding up the loading process in the event the manifest hasn't changed since the last
/// time a load was performed.
///
public class CachedManifestLoader: ManifestLoading {
    private let manifestLoader: ManifestLoading
    private let projectDescriptionHelpersHasher: ProjectDescriptionHelpersHashing
    private let helpersDirectoryLocator: HelpersDirectoryLocating
    private let fileSystem: FileSysteming
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let tuistVersion: String
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let helpersCache: ThreadSafe<[AbsolutePath: Task<String, any Error>]> = ThreadSafe([:])
    private let pluginsHashCache: ThreadSafe<Task<String?, any Error>?> = ThreadSafe(nil)
    private let cacheDirectory: ThrowableCaching<AbsolutePath>

    public convenience init(manifestLoader: ManifestLoading = ManifestLoader()) {
        self.init(
            manifestLoader: manifestLoader,
            projectDescriptionHelpersHasher: ProjectDescriptionHelpersHasher(),
            helpersDirectoryLocator: HelpersDirectoryLocator(),
            fileSystem: FileSystem(),
            cacheDirectoriesProvider: CacheDirectoriesProvider(),
            tuistVersion: Constants.version
        )
    }

    init(
        manifestLoader: ManifestLoading,
        projectDescriptionHelpersHasher: ProjectDescriptionHelpersHashing,
        helpersDirectoryLocator: HelpersDirectoryLocating,
        fileSystem: FileSysteming,
        cacheDirectoriesProvider: CacheDirectoriesProviding,
        tuistVersion: String
    ) {
        self.manifestLoader = manifestLoader
        self.projectDescriptionHelpersHasher = projectDescriptionHelpersHasher
        self.helpersDirectoryLocator = helpersDirectoryLocator
        self.fileSystem = fileSystem
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.tuistVersion = tuistVersion
        cacheDirectory = ThrowableCaching {
            try cacheDirectoriesProvider.cacheDirectory(for: .manifests)
        }
    }

    public func loadConfig(at path: AbsolutePath) async throws -> ProjectDescription.Config {
        try await load(manifest: .config, at: path, disableSandbox: true) {
            let projectDescriptionConfig = try await manifestLoader.loadConfig(at: path)
            return projectDescriptionConfig
        }
    }

    public func loadProject(at path: AbsolutePath, disableSandbox: Bool) async throws -> ProjectDescription.Project {
        try await load(manifest: .project, at: path, disableSandbox: disableSandbox) {
            try await manifestLoader.loadProject(at: path, disableSandbox: disableSandbox)
        }
    }

    public func loadWorkspace(at path: AbsolutePath, disableSandbox: Bool) async throws -> ProjectDescription.Workspace {
        try await load(manifest: .workspace, at: path, disableSandbox: disableSandbox) {
            try await manifestLoader.loadWorkspace(at: path, disableSandbox: disableSandbox)
        }
    }

    public func loadTemplate(at path: AbsolutePath) async throws -> ProjectDescription.Template {
        try await load(manifest: .template, at: path, disableSandbox: true) {
            try await manifestLoader.loadTemplate(at: path)
        }
    }

    public func loadPlugin(at path: AbsolutePath) async throws -> ProjectDescription.Plugin {
        try await load(manifest: .plugin, at: path, disableSandbox: true) {
            try await manifestLoader.loadPlugin(at: path)
        }
    }

    public func loadPackageSettings(at path: AbsolutePath, disableSandbox: Bool) async throws -> ProjectDescription
        .PackageSettings
    {
        try await load(manifest: .packageSettings, at: path, disableSandbox: disableSandbox) {
            try await manifestLoader.loadPackageSettings(at: path, disableSandbox: disableSandbox)
        }
    }

    public func loadPackage(at path: AbsolutePath, disableSandbox: Bool) async throws -> PackageInfo {
        try await load(manifest: .package, at: path, disableSandbox: disableSandbox) {
            try await manifestLoader.loadPackage(at: path, disableSandbox: disableSandbox)
        }
    }

    public func manifests(at path: AbsolutePath) async throws -> Set<Manifest> {
        try await manifestLoader.manifests(at: path)
    }

    public func validateHasRootManifest(at path: AbsolutePath) async throws {
        try await manifestLoader.validateHasRootManifest(at: path)
    }

    public func hasRootManifest(at path: AbsolutePath) async throws -> Bool {
        try await manifestLoader.hasRootManifest(at: path)
    }

    public func register(plugins: Plugins) throws {
        pluginsHashCache.mutate { $0 = Task { try await calculatePluginsHash(for: plugins) } }
        try manifestLoader.register(plugins: plugins)
    }

    // MARK: - Private

    private func load<T: Codable>(
        manifest: Manifest,
        at path: AbsolutePath,
        disableSandbox: Bool,
        loader: () async throws -> T
    ) async throws -> T {
        let manifestPathCandidates = [
            path.appending(component: manifest.fileName(path)),
            manifest.alternativeFileName(path).map { path.appending(component: $0) },
        ].compactMap { $0 }
        var manifestPath: AbsolutePath!

        for candidateManifestPath in manifestPathCandidates {
            if try await fileSystem.exists(candidateManifestPath) {
                manifestPath = candidateManifestPath
                break
            }
        }

        if manifestPath == nil {
            throw ManifestLoaderError.manifestNotFound(manifest, path)
        }

        let calculatedHashes = try? await calculateHashes(
            path: path,
            manifestPath: manifestPath,
            manifest: manifest,
            disableSandbox: disableSandbox
        )

        guard let hashes = calculatedHashes else {
            Logger.current.warning("Unable to calculate manifest hash at path: \(path)")
            return try await loader()
        }

        let cachedManifestPath = try cachedPath(for: manifestPath)
        if let cached: T = try await loadCachedManifest(
            at: cachedManifestPath,
            hashes: hashes
        ) {
            return cached
        }

        let loadedManifest = try await loader()

        try await cacheManifest(
            manifest: manifest,
            loadedManifest: loadedManifest,
            hashes: hashes,
            to: cachedManifestPath
        )

        return loadedManifest
    }

    private func calculateHashes(
        path: AbsolutePath,
        manifestPath: AbsolutePath,
        manifest: Manifest,
        disableSandbox: Bool
    ) async throws -> Hashes {
        let manifestHash = try calculateManifestHash(for: manifest, at: manifestPath)
        let helpersHash = try await calculateHelpersHash(at: path)
        let environmentHash = calculateEnvironmentHash()
        let disableSandboxHash = "\(disableSandbox)".md5

        return Hashes(
            manifestHash: manifestHash,
            helpersHash: helpersHash,
            pluginsHash: try await pluginsHashCache.value?.value,
            environmentHash: environmentHash,
            disableSandboxHash: disableSandboxHash
        )
    }

    private func calculateManifestHash(for manifest: Manifest, at path: AbsolutePath) throws -> Data {
        guard let hash = path.sha256() else {
            throw ManifestLoaderError.manifestCachingFailed(manifest, path)
        }
        return hash
    }

    private func calculateHelpersHash(at path: AbsolutePath) async throws -> String? {
        guard let helpersDirectory = try await helpersDirectoryLocator.locate(at: path) else {
            return nil
        }

        return try await helpersCache.mutate { cache in
            if let cached = cache[helpersDirectory] {
                return cached
            }

            let task = Task {
                try await projectDescriptionHelpersHasher.hash(helpersDirectory: helpersDirectory)
            }

            cache[helpersDirectory] = task

            return task
        }
        .value
    }

    private func calculatePluginsHash(for plugins: Plugins) async throws -> String? {
        let projectDescriptionHelpersHasher = projectDescriptionHelpersHasher
        return try await plugins.projectDescriptionHelpers
            .concurrentMap { try await projectDescriptionHelpersHasher.hash(helpersDirectory: $0.path) }
            .joined(separator: "-")
            .md5
    }

    private func calculateEnvironmentHash() -> String? {
        let tuistEnvVariables = Environment.current.manifestLoadingVariables.map { "\($0.key)=\($0.value)" }.sorted()
        guard !tuistEnvVariables.isEmpty else {
            return nil
        }
        return tuistEnvVariables.joined(separator: "-").md5
    }

    private func cachedPath(for manifestPath: AbsolutePath) throws -> AbsolutePath {
        let pathHash = manifestPath.pathString.md5
        let cacheVersion = CachedManifest.currentCacheVersion.description
        let fileName = [cacheVersion, pathHash].joined(separator: ".")
        return try cacheDirectory.value.appending(component: fileName)
    }

    private func loadCachedManifest<T: Decodable>(
        at cachedManifestPath: AbsolutePath,
        hashes: Hashes
    ) async throws -> T? {
        guard try await fileSystem.exists(cachedManifestPath) else {
            return nil
        }

        guard let data = try? await fileSystem.readFile(at: cachedManifestPath) else {
            return nil
        }

        guard let cachedManifest = try? decoder.decode(CachedManifest.self, from: data) else {
            return nil
        }

        guard cachedManifest.cacheVersion == CachedManifest.currentCacheVersion,
              cachedManifest.tuistVersion == tuistVersion,
              cachedManifest.hashes == hashes
        else {
            return nil
        }

        return try? decoder.decode(T.self, from: cachedManifest.manifest)
    }

    private func cacheManifest(
        manifest: Manifest,
        loadedManifest: some Encodable,
        hashes: Hashes,
        to cachedManifestPath: AbsolutePath
    ) async throws {
        let cachedManifest = CachedManifest(
            tuistVersion: tuistVersion,
            hashes: hashes,
            manifest: try encoder.encode(loadedManifest)
        )

        let cachedManifestData = try encoder.encode(cachedManifest)
        guard let cachedManifestContent = String(data: cachedManifestData, encoding: .utf8) else {
            throw ManifestLoaderError.manifestCachingFailed(manifest, cachedManifestPath)
        }
        do {
            try await write(cachedManifestContent: cachedManifestContent, to: cachedManifestPath)
        } catch let error as _NIOFileSystem.FileSystemError {
            if error.code == .fileAlreadyExists {
                Logger.current.debug("The manifest at \(cachedManifestPath) is already cached, skipping...")
            } else {
                throw error
            }
        }
    }

    private func write(cachedManifestContent: String, to cachedManifestPath: AbsolutePath) async throws {
        if try await !fileSystem.exists(cachedManifestPath.parentDirectory, isDirectory: true) {
            try await fileSystem.makeDirectory(at: cachedManifestPath)
        }
        if try await fileSystem.exists(cachedManifestPath) {
            try await fileSystem.remove(cachedManifestPath)
        }
        try await fileSystem.writeText(
            cachedManifestContent,
            at: cachedManifestPath
        )
    }
}

private struct Hashes: Equatable, Codable {
    var manifestHash: Data
    var helpersHash: String?
    var pluginsHash: String?
    var environmentHash: String?
    var disableSandboxHash: String
}

private struct CachedManifest: Codable {
    // Note: please bump the version in case the cache structure is modified.
    // This ensures older cache versions are not loaded using this structure.

    static let currentCacheVersion = 1

    var cacheVersion: Int = currentCacheVersion
    var tuistVersion: String
    var hashes: Hashes
    var manifest: Data
}
