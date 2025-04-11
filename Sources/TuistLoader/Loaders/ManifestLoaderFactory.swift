import Foundation
import ServiceContextModule
import TuistSupport

public final class ManifestLoaderFactory {
    public init() {}
    public func createManifestLoader() -> ManifestLoading {
        if ServiceContext.current!.environment!
            .tuistVariables[Constants.EnvironmentVariables.cacheManifests, default: "1"] == "1"
        {
            return CachedManifestLoader()
        }
        return ManifestLoader()
    }
}
