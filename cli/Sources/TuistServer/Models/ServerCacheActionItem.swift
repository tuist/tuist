import Foundation

/// Server cache action item
public struct ServerCacheActionItem: Equatable {
    public init(
        hash: String
    ) {
        self.hash = hash
    }

    public let hash: String

    init(_ cacheActionItem: Components.Schemas.CacheActionItem) {
        hash = cacheActionItem.hash
    }

    #if DEBUG
        public static func test(
            hash: String = "hash"
        ) -> Self {
            .init(
                hash: hash
            )
        }
    #endif
}
