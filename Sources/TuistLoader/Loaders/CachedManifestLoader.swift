import Foundation
import ProjectDescription
import TSCBasic
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
    private let cacheDirectory: AbsolutePath
    private let fileHandler: FileHandling
    private let environment: Environmenting
    private let tuistVersion: String
    private let decoder: JSONDecoder = JSONDecoder()
    private let encoder: JSONEncoder = JSONEncoder()
    private var helpersCache: [AbsolutePath: String?] = [:]

    public convenience init(manifestLoader: ManifestLoading = ManifestLoader()) {
        let environment = TuistSupport.Environment.shared
        self.init(manifestLoader: manifestLoader,
                  projectDescriptionHelpersHasher: ProjectDescriptionHelpersHasher(),
                  helpersDirectoryLocator: HelpersDirectoryLocator(),
                  cacheDirectory: environment.cacheDirectory.appending(component: "Manifests"),
                  fileHandler: FileHandler.shared,
                  environment: environment,
                  tuistVersion: Constants.version)
    }

    init(manifestLoader: ManifestLoading,
         projectDescriptionHelpersHasher: ProjectDescriptionHelpersHashing,
         helpersDirectoryLocator: HelpersDirectoryLocating,
         cacheDirectory: AbsolutePath,
         fileHandler: FileHandling,
         environment: Environmenting,
         tuistVersion: String)
    {
        self.manifestLoader = manifestLoader
        self.projectDescriptionHelpersHasher = projectDescriptionHelpersHasher
        self.helpersDirectoryLocator = helpersDirectoryLocator
        self.cacheDirectory = cacheDirectory
        self.fileHandler = fileHandler
        self.environment = environment
        self.tuistVersion = tuistVersion
    }

    public func loadConfig(at path: AbsolutePath) throws -> Config {
        try load(manifest: .config, at: path) {
            try manifestLoader.loadConfig(at: path)
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

    public func loadSetup(at path: AbsolutePath) throws -> [Upping] {
        try manifestLoader.loadSetup(at: path)
    }

    public func loadTemplate(at path: AbsolutePath) throws -> Template {
        try load(manifest: .template, at: path) {
            try manifestLoader.loadTemplate(at: path)
        }
    }

    public func manifests(at path: AbsolutePath) -> Set<Manifest> {
        manifestLoader.manifests(at: path)
    }

    // MARK: - Private

    private func load<T: Codable>(manifest: Manifest, at path: AbsolutePath, loader: () throws -> T) throws -> T {
        guard let manifestPath = findManifestPath(for: manifest, at: path) else {
            throw ManifestLoaderError.manifestNotFound(manifest, path)
        }

        let calculatedHashes = try? calculateHashes(path: path,
                                                    manifestPath: manifestPath,
                                                    manifest: manifest)

        guard let hashes = calculatedHashes else {
            logger.warning("Unable to calculate manifest hash at path: \(path)")
            return try loader()
        }

        let cachedManifestPath = cachedPath(for: manifestPath)
        if let cached: T = loadCachedManifest(at: cachedManifestPath,
                                              hashes: hashes)
        {
            return cached
        }

        let loadedManifest = try loader()

        try cacheManifest(manifest: manifest,
                          loadedManifest: loadedManifest,
                          hashes: hashes,
                          to: cachedManifestPath)

        return loadedManifest
    }

    private func findManifestPath(for manifest: Manifest, at path: AbsolutePath) -> AbsolutePath? {
        let manifestFileNames = [manifest.fileName, manifest.deprecatedFileName]
        return manifestFileNames
            .compactMap { $0 }
            .map { path.appending(component: $0) }
            .first(where: { fileHandler.exists($0) })
    }

    private func calculateHashes(path: AbsolutePath,
                                 manifestPath: AbsolutePath,
                                 manifest: Manifest) throws -> Hashes
    {
        let manifestHash = try calculateManifestHash(for: manifest, at: manifestPath)
        let helpersHash = try calculateHelpersHash(at: path)
        let environmentHash = calculateEnvironmentHash()

        return Hashes(manifestHash: manifestHash,
                      helpersHash: helpersHash,
                      environmentHash: environmentHash)
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

    private func calculateEnvironmentHash() -> String? {
        let tuistEnvVariables = environment.tuistVariables.map { "\($0.key)=\($0.value)" }.sorted()
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

    private func loadCachedManifest<T: Decodable>(at cachedManifestPath: AbsolutePath,
                                                  hashes: Hashes) -> T?
    {
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

    private func cacheManifest<T: Encodable>(manifest: Manifest,
                                             loadedManifest: T,
                                             hashes: Hashes,
                                             to cachedManifestPath: AbsolutePath) throws
    {
        let cachedManifest = CachedManifest(tuistVersion: tuistVersion,
                                            hashes: hashes,
                                            manifest: try encoder.encode(loadedManifest))

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
