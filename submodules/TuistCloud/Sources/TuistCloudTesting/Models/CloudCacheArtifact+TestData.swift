import Foundation
import TuistCloud
import TuistSupport

extension CloudCacheArtifact {
    public static func test(
        url: URL = URL(string: Constants.tuistCloudURL)!,
        expiresAt: Int = 0
    ) -> Self {
        .init(
            url: url,
            expiresAt: expiresAt
        )
    }
}
