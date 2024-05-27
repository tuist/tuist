import TuistCore

extension Components.Schemas.CacheCategory {
    init(_ cacheCategory: CacheCategory.App) {
        switch cacheCategory {
        case .binaries:
            self = .builds
        case .selectiveTests:
            self = .tests
        }
    }
}
