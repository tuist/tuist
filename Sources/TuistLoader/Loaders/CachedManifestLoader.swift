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
    private let decoder: JSONDecoder = JSONDecoder()
    private let encoder: JSONEncoder = JSONEncoder()
    private var helpersCache: [AbsolutePath: String?] = [:]

    public convenience init(manifestLoader: ManifestLoading = ManifestLoader()) {
        self.init(manifestLoader: manifestLoader,
                  projectDescriptionHelpersHasher: ProjectDescriptionHelpersHasher(),
                  helpersDirectoryLocator: HelpersDirectoryLocator(),
                  cacheDirectory: Environment.shared.cacheDirectory.appending(component: "Manifests"),
                  fileHandler: FileHandler.shared)
    }

    init(manifestLoader: ManifestLoading,
         projectDescriptionHelpersHasher: ProjectDescriptionHelpersHashing,
         helpersDirectoryLocator: HelpersDirectoryLocating,
         cacheDirectory: AbsolutePath,
         fileHandler: FileHandling) {
        self.manifestLoader = manifestLoader
        self.projectDescriptionHelpersHasher = projectDescriptionHelpersHasher
        self.helpersDirectoryLocator = helpersDirectoryLocator
        self.cacheDirectory = cacheDirectory
        self.fileHandler = fileHandler
    }

    public func loadConfig(at path: AbsolutePath) throws -> Config {
        try manifestLoader.loadConfig(at: path)
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
        let manifestPath = path.appending(component: manifest.fileName)
        guard fileHandler.exists(manifestPath) else {
            throw ManifestLoaderError.manifestNotFound(manifest, path)
        }

        let manifestHash = try calculateManifestHash(for: manifest, at: manifestPath)
        let helpersHash = try calculateHelpersCache(at: path)

        let cachedManifestPath = cachedPath(for: manifestPath)
        if let cached: T = loadCachedManifest(at: cachedManifestPath,
                                              manifestHash: manifestHash,
                                              helpersHash: helpersHash) {
            return cached
        }

        let loadedManifest = try loader()

        try cacheManifest(manifest: manifest,
                          loadedManifest: loadedManifest,
                          manifestHash: manifestHash,
                          helpersHash: helpersHash,
                          to: cachedManifestPath)

        return loadedManifest
    }

    private func calculateManifestHash(for manifest: Manifest, at path: AbsolutePath) throws -> Data {
        guard let hash = path.sha256() else {
            throw ManifestLoaderError.manifestCachingFailed(manifest, path)
        }
        return hash
    }

    private func calculateHelpersCache(at path: AbsolutePath) throws -> String? {
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

    private func cachedPath(for manifestPath: AbsolutePath) -> AbsolutePath {
        let pathHash = manifestPath.pathString.md5
        let cacheVersion = CachedManifest.currentVersion.description
        let fileName = [cacheVersion, pathHash].joined(separator: ".")
        return cacheDirectory.appending(component: fileName)
    }

    private func loadCachedManifest<T: Decodable>(at cachedManifestPath: AbsolutePath,
                                                  manifestHash: Data,
                                                  helpersHash: String?) -> T? {
        guard fileHandler.exists(cachedManifestPath) else {
            return nil
        }

        guard let data = try? fileHandler.readFile(cachedManifestPath) else {
            return nil
        }

        guard let cachedManifest = try? decoder.decode(CachedManifest.self, from: data) else {
            return nil
        }

        guard cachedManifest.version == CachedManifest.currentVersion,
            cachedManifest.helpersHash == helpersHash,
            cachedManifest.manifestHash == manifestHash else {
            return nil
        }

        return try? decoder.decode(T.self, from: cachedManifest.manifest)
    }

    private func cacheManifest<T: Encodable>(manifest: Manifest,
                                             loadedManifest: T,
                                             manifestHash: Data,
                                             helpersHash: String?,
                                             to cachedManifestPath: AbsolutePath) throws {
        let cachedManifest = CachedManifest(manifestHash: manifestHash,
                                            helpersHash: helpersHash,
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

private struct CachedManifest: Codable {
    static let currentVersion = 1
    var version: Int = currentVersion
    var manifestHash: Data
    var helpersHash: String?
    var manifest: Data
}
