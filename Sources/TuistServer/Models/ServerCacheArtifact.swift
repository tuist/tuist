import Foundation
import TuistSupport

enum ServerCacheArtifactError: FatalError, Equatable {
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

/// Server cache artifact
public struct ServerCacheArtifact: Codable {
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

extension ServerCacheArtifact {
    init(_ cacheArtifact: Components.Schemas.CacheArtifactDownloadURL) throws {
        guard let url = URL(string: cacheArtifact.data.url)
        else { throw ServerCacheArtifactError.invalidURL(cacheArtifact.data.url) }
        self.url = url
        expiresAt = Int(cacheArtifact.data.expires_at)
    }
}

#if DEBUG
    extension ServerCacheArtifact {
        public static func test(
            url: URL = Constants.URLs.production,
            expiresAt: Int = 0
        ) -> Self {
            .init(
                url: url,
                expiresAt: expiresAt
            )
        }
    }
#endif
