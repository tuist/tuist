import TuistAutomation
import TuistCache

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
    /// - Returns: A cache controller instance.
    func makeForSimulatorFramework() -> CacheControlling {
        let frameworkBuilder = CacheFrameworkBuilder(xcodeBuildController: XcodeBuildController())
        return CacheController(cache: cache, artifactBuilder: frameworkBuilder)
    }

    /// Returns a cache controller that uses xcframeworks built for the simulator and device architectures.
    /// - Returns: A cache controller instance.
    func makeForXCFramework() -> CacheControlling {
        let frameworkBuilder = CacheXCFrameworkBuilder(xcodeBuildController: XcodeBuildController())
        return CacheController(cache: cache, artifactBuilder: frameworkBuilder)
    }
}
