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

    func run(
        path: String?,
        profile: String?,
        xcframeworks: Bool,
        destination: CacheXCFrameworkDestination,
        targets: Set<String>,
        dependenciesOnly: Bool
    ) async throws {
        let path = try self.path(path)
        let config = try configLoader.loadConfig(path: path)
        let storages = try CacheStorageProvider(config: config).storages()
        let cache = Cache(storages: storages)
        let contentHasher = CacheContentHasher()
        let cacheController: CacheControlling
        if xcframeworks {
            cacheController = try xcframeworkCacheController(
                cache: cache,
                destination: destination,
                contentHasher: contentHasher
            )
        } else {
            cacheController = simulatorFrameworkCacheController(cache: cache, contentHasher: contentHasher)
        }

        let profile = try CacheProfileResolver().resolveCacheProfile(named: profile, from: config)
        try await cacheController.cache(
            config: config,
            path: path,
            cacheProfile: profile,
            includedTargets: targets,
            dependenciesOnly: dependenciesOnly
        )
    }

    // MARK: - Fileprivate

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path = path {
            return try AbsolutePath(validating: path, relativeTo: currentPath)
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

    private func xcframeworkCacheController(
        cache: CacheStoring,
        destination: CacheXCFrameworkDestination,
        contentHasher: ContentHashing
    ) throws -> CacheControlling {
        let frameworkBuilder = CacheXCFrameworkBuilder(
            xcodeBuildController: XcodeBuildController(),
            destination: destination
        )
        let bundleBuilder = CacheBundleBuilder(xcodeBuildController: XcodeBuildController())
        return CacheController(
            cache: cache,
            artifactBuilder: frameworkBuilder,
            bundleArtifactBuilder: bundleBuilder,
            contentHasher: contentHasher
        )
    }
}
