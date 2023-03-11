import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import struct TuistGraph.Config
import struct TuistGraph.Plugins
import TuistSupport

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
    private let fileHandler: FileHandling
    private let environment: Environmenting
    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring
    private let tuistVersion: String
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    @Atomic private var helpersCache: [AbsolutePath: String?] = [:]
    @Atomic private var pluginsHashCache: String?
    @Atomic private var cacheDirectory: AbsolutePath!

    public convenience init(manifestLoader: ManifestLoading = ManifestLoader()) {
        let environment = TuistSupport.Environment.shared
        self.init(
            manifestLoader: manifestLoader,
            projectDescriptionHelpersHasher: ProjectDescriptionHelpersHasher(),
            helpersDirectoryLocator: HelpersDirectoryLocator(),
            fileHandler: FileHandler.shared,
            environment: environment,
            cacheDirectoryProviderFactory: CacheDirectoriesProviderFactory(),
            tuistVersion: Constants.version
        )
    }

    init(
        manifestLoader: ManifestLoading,
        projectDescriptionHelpersHasher: ProjectDescriptionHelpersHashing,
        helpersDirectoryLocator: HelpersDirectoryLocating,
        fileHandler: FileHandling,
        environment: Environmenting,
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring,
        tuistVersion: String
    ) {
        self.manifestLoader = manifestLoader
        self.projectDescriptionHelpersHasher = projectDescriptionHelpersHasher
        self.helpersDirectoryLocator = helpersDirectoryLocator
        self.fileHandler = fileHandler
        self.environment = environment
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
        self.tuistVersion = tuistVersion
    }

    public func loadConfig(at path: AbsolutePath) throws -> ProjectDescription.Config {
        try load(manifest: .config, at: path) {
            let projectDescriptionConfig = try manifestLoader.loadConfig(at: path)
            let config = try TuistGraph.Config.from(manifest: projectDescriptionConfig, at: path)
            cacheDirectory = try cacheDirectoryProviderFactory.cacheDirectories(config: config).cacheDirectory(for: .manifests)
            return projectDescriptionConfig
        }
    }

    public func loadProject(at path: AbsolutePath) throws -> Project {
        try load(manifest: .project, at: path) {
            try manifestLoader.loadProject(at: path)
        }
    }

    public func loadWorkspace(at path: AbsolutePath) throws -> Workspace {
        try load(manifest: .workspace, at: path) {
            try manifestLoader.loadWorkspace(at: path)
        }
    }

    public func loadTemplate(at path: AbsolutePath) throws -> Template {
        try load(manifest: .template, at: path) {
            try manifestLoader.loadTemplate(at: path)
        }
    }

    public func loadPlugin(at path: AbsolutePath) throws -> Plugin {
        try load(manifest: .plugin, at: path) {
            try manifestLoader.loadPlugin(at: path)
        }
    }

    public func loadDependencies(at path: AbsolutePath) throws -> Dependencies {
        try manifestLoader.loadDependencies(at: path)
    }

    public func manifests(at path: AbsolutePath) -> Set<Manifest> {
        manifestLoader.manifests(at: path)
    }

    public func validateHasProjectOrWorkspaceManifest(at path: AbsolutePath) throws {
        try manifestLoader.validateHasProjectOrWorkspaceManifest(at: path)
    }

    public func register(plugins: Plugins) throws {
        pluginsHashCache = try calculatePluginsHash(for: plugins)
        try manifestLoader.register(plugins: plugins)
    }

    // MARK: - Private

    private func load<T: Codable>(manifest: Manifest, at path: AbsolutePath, loader: () throws -> T) throws -> T {
        if cacheDirectory == nil {
            cacheDirectory = try cacheDirectoryProviderFactory.cacheDirectories(config: nil).cacheDirectory(for: .manifests)
        }

        let manifestPath = path.appending(component: manifest.fileName(path))
        guard fileHandler.exists(manifestPath) else {
            throw ManifestLoaderError.manifestNotFound(manifest, path)
        }

        let calculatedHashes = try? calculateHashes(
            path: path,
            manifestPath: manifestPath,
            manifest: manifest
        )

        guard let hashes = calculatedHashes else {
            logger.warning("Unable to calculate manifest hash at path: \(path)")
            return try loader()
        }

        let cachedManifestPath = cachedPath(for: manifestPath)
        if let cached: T = loadCachedManifest(
            at: cachedManifestPath,
            hashes: hashes
        ) {
            return cached
        }

        let loadedManifest = try loader()

        try cacheManifest(
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
        manifest: Manifest
    ) throws -> Hashes {
        let manifestHash = try calculateManifestHash(for: manifest, at: manifestPath)
        let helpersHash = try calculateHelpersHash(at: path)
        let environmentHash = calculateEnvironmentHash()

        return Hashes(
            manifestHash: manifestHash,
            helpersHash: helpersHash,
            pluginsHash: pluginsHashCache,
            environmentHash: environmentHash
        )
    }

    private func calculateManifestHash(for manifest: Manifest, at path: AbsolutePath) throws -> Data {
        guard let hash = path.sha256() else {
            throw ManifestLoaderError.manifestCachingFailed(manifest, path)
        }
        return hash
    }

    private func calculateHelpersHash(at path: AbsolutePath) throws -> String? {
        guard let helpersDirectory = helpersDirectoryLocator.locate(at: path) else {
            return nil
        }

        if let cached = helpersCache[helpersDirectory] {
            return cached
        }

        let hash = try projectDescriptionHelpersHasher.hash(helpersDirectory: helpersDirectory)
        helpersCache[helpersDirectory] = hash

        return hash
    }

    private func calculatePluginsHash(for plugins: Plugins) throws -> String? {
        try plugins.projectDescriptionHelpers
            .map { try projectDescriptionHelpersHasher.hash(helpersDirectory: $0.path) }
            .joined(separator: "-")
            .md5
    }

    private func calculateEnvironmentHash() -> String? {
        let tuistEnvVariables = environment.manifestLoadingVariables.map { "\($0.key)=\($0.value)" }.sorted()
        guard !tuistEnvVariables.isEmpty else {
            return nil
        }
        return tuistEnvVariables.joined(separator: "-").md5
    }

    private func cachedPath(for manifestPath: AbsolutePath) -> AbsolutePath {
        let pathHash = manifestPath.pathString.md5
        let cacheVersion = CachedManifest.currentCacheVersion.description
        let fileName = [cacheVersion, pathHash].joined(separator: ".")
        return cacheDirectory.appending(component: fileName)
    }

    private func loadCachedManifest<T: Decodable>(
        at cachedManifestPath: AbsolutePath,
        hashes: Hashes
    ) -> T? {
        guard fileHandler.exists(cachedManifestPath) else {
            return nil
        }

        guard let data = try? fileHandler.readFile(cachedManifestPath) else {
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

    private func cacheManifest<T: Encodable>(
        manifest: Manifest,
        loadedManifest: T,
        hashes: Hashes,
        to cachedManifestPath: AbsolutePath
    ) throws {
        let cachedManifest = CachedManifest(
            tuistVersion: tuistVersion,
            hashes: hashes,
            manifest: try encoder.encode(loadedManifest)
        )

        let cachedManifestData = try encoder.encode(cachedManifest)
        guard let cachedManifestContent = String(data: cachedManifestData, encoding: .utf8) else {
            throw ManifestLoaderError.manifestCachingFailed(manifest, cachedManifestPath)
        }

        try fileHandler.touch(cachedManifestPath)
        try fileHandler.write(
            cachedManifestContent,
            path: cachedManifestPath,
            atomically: true
        )
    }
}

private struct Hashes: Equatable, Codable {
    var manifestHash: Data
    var helpersHash: String?
    var pluginsHash: String?
    var environmentHash: String?
}

private struct CachedManifest: Codable {
    // Note: please bump the version in case the cache structure is modifed
    // this ensures older cache versions are not loaded using this structure
    static let currentCacheVersion = 1
    var cacheVersion: Int = currentCacheVersion
    var tuistVersion: String
    var hashes: Hashes
    var manifest: Data
}
