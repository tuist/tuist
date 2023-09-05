import Foundation
import TuistSupport

enum CloudCacheArtifactError: FatalError, Equatable {
    case invalidURL(String)

    var description: String {
        switch self {
        case let .invalidURL(url):
            return "Invalid URL for the remote cache artifact: \(url)."
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidURL:
            return .bug
        }
    }
}

/// Cloud cache artifact
public struct CloudCacheArtifact: Codable {
    public init(
        url: URL,
        expiresAt: Int
    ) {
        self.url = url
        self.expiresAt = expiresAt
    }

    public let url: URL
    public let expiresAt: Int
}

extension CloudCacheArtifact {
    init(_ cacheArtifact: Components.Schemas.CacheArtifact) throws {
        guard
            let url = URL(string: cacheArtifact.data.url)
        else { throw CloudCacheArtifactError.invalidURL(cacheArtifact.data.url) }
        self.url = url
        expiresAt = Int(cacheArtifact.data.expires_at)
    }
}
