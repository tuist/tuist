import Foundation
import TuistSupport

public final class ManifestLoaderFactory {
    private let useCache: Bool
    public convenience init() {
        let cacheSetting = Environment.shared.tuistConfigVariables[Constants.EnvironmentVariables.cacheManifests]
        self.init(useCache: cacheSetting.map { $0 == "1" } ?? false)
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
