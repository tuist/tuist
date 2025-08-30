import Foundation
import TuistSupport

public final class ManifestLoaderFactory {
    private let useCache: Bool
    public convenience init() {
        let useCache = if Environment.current.variables[Constants.EnvironmentVariables.cacheManifests] != nil {
            Environment.current.isVariableTruthy(Constants.EnvironmentVariables.cacheManifests)
        } else {
            true
        }
        self.init(useCache: useCache)
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
