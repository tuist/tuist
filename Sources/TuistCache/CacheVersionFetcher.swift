import Foundation
import XcodeGraph

protocol CacheVersionFetching {
    func version() -> CacheVersion
}

enum CacheVersion: String, Equatable, Hashable {
    /**
     This is the first version that we introduced that used frameworks, bundles, and xcframeworks when developers opted into it.
     However:
        - It did not support multi-platform targetes
        - The solution to support multiple architectures, xcframeworks, was not suitable for this problem, causing compilation issues.
     */
    case version1 = "1.0.0"
    /**
     This version was introduced to support multi-platform caching and drop support for xcframeworks.
     */
    case version2 = "2"
}

struct CacheVersionFetcher: CacheVersionFetching {
    func version() -> CacheVersion {
        .version2
    }
}
