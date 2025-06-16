import Foundation
import TuistSupport

public final class ManifestLoaderFactory {
    private let useCache: Bool
    public convenience init() {
        self.init(useCache: Environment.current.isVariableTruthy(Constants.EnvironmentVariables.cacheManifests))
    }

    public init(useCache: Bool) {
        self.useCache = useCache
    }

    public func createManifestLoader() -> ManifestLoading {
        if useCache {
            return CachedManifestLoader()
        }
        return ManifestLoader()
    }
}
