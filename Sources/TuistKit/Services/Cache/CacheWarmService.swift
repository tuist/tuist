import Foundation
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport

final class CacheWarmService {
    private let configLoader: ConfigLoading

    init() {
        configLoader = ConfigLoader(manifestLoader: ManifestLoader())
    }

    func run(path: String?, profile: String?, xcframeworks: Bool, targets: Set<String>, dependenciesOnly: Bool) throws {
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
        try cacheController.cache(
            config: config,
            path: path,
            cacheProfile: profile,
            includedTargets: targets,
            dependenciesOnly: dependenciesOnly
        )
    }

    // MARK: - Fileprivate

    fileprivate func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: currentPath)
        } else {
            return currentPath
        }
    }

    fileprivate var currentPath: AbsolutePath {
        FileHandler.shared.currentPath
    }

    fileprivate func simulatorFrameworkCacheController(cache: CacheStoring, contentHasher: ContentHashing) -> CacheControlling {
        let frameworkBuilder = CacheFrameworkBuilder(xcodeBuildController: XcodeBuildController())
        let bundleBuilder = CacheBundleBuilder(xcodeBuildController: XcodeBuildController())
        return CacheController(
            cache: cache,
            artifactBuilder: frameworkBuilder,
            bundleArtifactBuilder: bundleBuilder,
            contentHasher: contentHasher
        )
    }

    fileprivate func xcframeworkCacheController(cache: CacheStoring, contentHasher: ContentHashing) -> CacheControlling {
        let frameworkBuilder = CacheXCFrameworkBuilder(xcodeBuildController: XcodeBuildController())
        let bundleBuilder = CacheBundleBuilder(xcodeBuildController: XcodeBuildController())
        return CacheController(
            cache: cache,
            artifactBuilder: frameworkBuilder,
            bundleArtifactBuilder: bundleBuilder,
            contentHasher: contentHasher
        )
    }
}
