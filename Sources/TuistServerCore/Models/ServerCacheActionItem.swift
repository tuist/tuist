import Foundation

/// Server cache action item
public struct ServerCacheActionItem: Equatable {
    public init(
        hash: String
    ) {
        self.hash = hash
    }

    public let hash: String
}

extension ServerCacheActionItem {
    public init(_ cacheActionItem: Components.Schemas.CacheActionItem) {
        hash = cacheActionItem.hash
    }
}

#if DEBUG
    extension ServerCacheActionItem {
        public static func test(
            hash: String = "hash"
        ) -> Self {
            .init(
                hash: hash
            )
        }
    }
#endif
