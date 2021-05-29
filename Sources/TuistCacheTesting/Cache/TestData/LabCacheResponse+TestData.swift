import Foundation
@testable import TuistCache

extension LabCacheResponse {
    public static func test(url: URL = URL.test(), expiresAt: TimeInterval = 0) -> LabCacheResponse {
        LabCacheResponse(
            url: url,
            expiresAt: expiresAt
        )
    }
}
