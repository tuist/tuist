import TuistAutomation
import TuistCache

final class CacheControllerFactory {
    let cache: CacheStoring

    init(cache: CacheStoring) {
        self.cache = cache
    }

    func makeForSimulatorFramework() -> CacheControlling {
        let frameworkBuilder = FrameworkBuilder(xcodeBuildController: XcodeBuildController())
        return CacheController(cache: cache, artifactBuilder: frameworkBuilder)
    }

    func makeForXCFramework() -> CacheControlling {
        let frameworkBuilder = XCFrameworkBuilder(xcodeBuildController: XcodeBuildController())
        return CacheController(cache: cache, artifactBuilder: frameworkBuilder)
    }
}
