import Foundation
import TuistSupport

public final class ManifestLoaderFactory {
    public init() {}
    
    public func createManifestLoader(context: Context) -> ManifestLoading {
        if context.environment.useManifestsCache {
            return CachedManifestLoader()
        }
        return ManifestLoader()
    }
}
