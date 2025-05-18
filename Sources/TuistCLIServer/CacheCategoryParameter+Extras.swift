import TuistCore
import TuistServer

extension Components.Schemas.CacheCategory {
    init(_ cacheCategory: RemoteCacheCategory) {
        switch cacheCategory {
        case .binaries:
            self = .builds
        case .selectiveTests:
            self = .tests
        }
    }
}
