import Foundation
import TuistSupport

public final class ManifestLoaderFactory {
    private let useCache: Bool
    public convenience init() {
        let cacheSetting = Environment.shared.tuistConfigVariables[Constants.EnvironmentVariables.cacheManifests, default: "1"]
        self.init(useCache: cacheSetting == "1")
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
