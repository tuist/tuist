import Foundation
import Path

public struct SelectiveTestsAnalytics: Equatable {
    public let hashes: [AbsolutePath: [String: String]]
    public let cacheItems: [AbsolutePath: [String: CacheItem]]

    public init(
        hashes: [AbsolutePath: [String: String]],
        cacheItems: [AbsolutePath: [String: CacheItem]]
    ) {
        self.hashes = hashes
        self.cacheItems = cacheItems
    }
}
