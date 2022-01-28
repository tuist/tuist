import Foundation
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCore
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistSupport

final class CacheWarmService {
    private let configLoader: ConfigLoading
    private let manifestLoader: ManifestLoading
    private let pluginService: PluginServicing

    init() {
        configLoader = ConfigLoader(manifestLoader: ManifestLoader())
        manifestLoader = ManifestLoader()
        pluginService = PluginService()
    }

    func run(path: String?, profile: String?, xcframeworks: Bool, targets: Set<String>, dependenciesOnly: Bool) async throws {
        let path = self.path(path)
        let config = try configLoader.loadConfig(path: path)
        let cache = Cache(storageProvider: CacheStorageProvider(config: config))
        let contentHasher = CacheContentHasher()
        let cacheController: CacheControlling
        if xcframeworks {
            cacheController = xcframeworkCacheController(cache: cache, contentHasher: contentHasher)
        } else {
            cacheController = simulatorFrameworkCacheController(cache: cache, contentHasher: contentHasher)
        }

        let profile = try CacheProfileResolver().resolveCacheProfile(named: profile, from: config)
        try await cacheController.cache(
            config: config,
            path: path,
            cacheProfile: profile,
            includedTargets: targets.isEmpty ? try projectTargets(at: path, config: config) : targets,
            dependenciesOnly: dependenciesOnly
        )
    }

    // MARK: - Fileprivate

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: currentPath)
        } else {
            return currentPath
        }
    }

    private var currentPath: AbsolutePath {
        FileHandler.shared.currentPath
    }

    private func simulatorFrameworkCacheController(cache: CacheStoring, contentHasher: ContentHashing) -> CacheControlling {
        let frameworkBuilder = CacheFrameworkBuilder(xcodeBuildController: XcodeBuildController())
        let bundleBuilder = CacheBundleBuilder(xcodeBuildController: XcodeBuildController())
        return CacheController(
            cache: cache,
            artifactBuilder: frameworkBuilder,
            bundleArtifactBuilder: bundleBuilder,
            contentHasher: contentHasher
        )
    }

    private func xcframeworkCacheController(cache: CacheStoring, contentHasher: ContentHashing) -> CacheControlling {
        let frameworkBuilder = CacheXCFrameworkBuilder(xcodeBuildController: XcodeBuildController())
        let bundleBuilder = CacheBundleBuilder(xcodeBuildController: XcodeBuildController())
        return CacheController(
            cache: cache,
            artifactBuilder: frameworkBuilder,
            bundleArtifactBuilder: bundleBuilder,
            contentHasher: contentHasher
        )
    }

    private func projectTargets(at path: AbsolutePath, config: Config) throws -> Set<String> {
        let plugins = try pluginService.loadPlugins(using: config)
        try manifestLoader.register(plugins: plugins)
        let manifests = manifestLoader.manifests(at: path)

        let projects: [AbsolutePath]
        if manifests.contains(.workspace) {
            let workspace = try manifestLoader.loadWorkspace(at: path)
            projects = workspace.projects.flatMap { project in
                FileHandler.shared.glob(path, glob: project.pathString).filter {
                    FileHandler.shared.isFolder($0) && manifestLoader.manifests(at: $0).contains(.project)
                }
            }
        } else if manifests.contains(.project) {
            projects = [path]
        } else {
            throw ManifestLoaderError.manifestNotFound(path)
        }

        return try Set(projects.flatMap { try manifestLoader.loadProject(at: $0).targets.map(\.name) })
    }
}
