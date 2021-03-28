import TuistAutomation
import TuistCache
import TuistCore
import TuistSupport

/// A factory that returns cache controllers for different type of pre-built artifacts.
final class CacheControllerFactory {
    /// Cache instance
    let cache: CacheStoring

    /// Default constructor.
    /// - Parameter cache: Cache instance.
    init(cache: CacheStoring) {
        self.cache = cache
    }

    /// Returns a cache controller that uses frameworks built for the simulator architecture.
    /// - Parameter contentHasher: Content hasher.
    /// - Returns: A cache controller instance.
    func makeForSimulatorFramework(contentHasher: ContentHashing) -> CacheControlling {
        let frameworkBuilder = CacheFrameworkBuilder(xcodeBuildController: XcodeBuildController())
        return CacheController(cache: cache, artifactBuilder: frameworkBuilder, contentHasher: contentHasher)
    }

    /// Returns a cache controller that uses xcframeworks built for the simulator and device architectures.
    /// - Parameter contentHasher: Content hasher.
    /// - Returns: Instance of the cache controller.
    func makeForXCFramework(contentHasher: ContentHashing) -> CacheControlling {
        let frameworkBuilder = CacheXCFrameworkBuilder(xcodeBuildController: XcodeBuildController())
        return CacheController(cache: cache, artifactBuilder: frameworkBuilder, contentHasher: contentHasher)
    }
}
