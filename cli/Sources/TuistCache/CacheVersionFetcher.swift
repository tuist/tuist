import Foundation

protocol CacheVersionFetching {
    func version() -> CacheVersion
}

enum CacheVersion: String, Equatable, Hashable {
    /// This is the first version that we introduced that used frameworks, bundles, and xcframeworks when developers opted into
    /// it.
    /// However:
    ///    - It did not support multi-platform targets.
    ///    - The solution to support multiple architectures, xcframeworks, was not suitable for this problem, causing compilation
    /// issues.
    case version1 = "1.0.0"

    /// This version was introduced to support multi-platform caching and drop support for xcframeworks.
    case version2 = "2"

    /// We defaulted to cache for only one architecture, and gave developers the option to opt into more (PR:
    /// https://github.com/tuist/tuist/pull/7977)
    /// but that caused incompatibilities in the graph edges (e.g. x86_64 linking against arm64), so we had to revert this
    /// decision (PR: https://github.com/tuist/tuist/pull/8094).
    /// Because the cache might have gotten polluted, for examle if it was warmed from x86_64 and consumed from arm64, it's
    /// important to bump the cache version to
    /// flag those artifacts as invalid.
    case version3 = "3"
}

struct CacheVersionFetcher: CacheVersionFetching {
    func version() -> CacheVersion {
        .version3
    }
}
