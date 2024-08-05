import Foundation
import Mockable
import Path
import TuistSupport

enum RemoteArtifactDownloaderError: FatalError, Equatable {
    case urlSessionError(url: URL, httpMethod: String, description: String)
    case noURLResponse(URL?)

    var type: ErrorType {
        switch self {
        case .urlSessionError: return .abort
        case .noURLResponse: return .abort
        }
    }

    var description: String {
        switch self {
        case let .urlSessionError(url, httpMethod, error):
            return "Received a session error when sending \(httpMethod) request to \(url.absoluteString): \(error)"
        case let .noURLResponse(url):
            if let url {
                return "The response from request to URL \(url.absoluteString) doesnt' have the expected type HTTPURLResponse"
            } else {
                return "Received a response that doesn't have the expected type HTTPURLResponse"
            }
        }
    }
}

@Mockable
public protocol RemoteArtifactDownloading {
    func download(url: URL) async throws -> AbsolutePath?
}

public struct RemoteArtifactDownloader: RemoteArtifactDownloading {
    private let urlSession: URLSession

    public init() {
        self.init(urlSession: URLSession.shared)
    }

    init(urlSession: URLSession) {
        self.urlSession = urlSession
    }

    public func download(url: URL) async throws -> AbsolutePath? {
        let request = URLRequest(url: url)
        do {
            let (localUrl, response) = try await urlSession.download(for: request)
            guard let urlResponse = response as? HTTPURLResponse else {
                throw RemoteArtifactDownloaderError.noURLResponse(request.url)
            }
            if (200 ..< 300).contains(urlResponse.statusCode) {
                return try AbsolutePath(validating: localUrl.path)
            } else if urlResponse.statusCode == 404 {
                return nil
            } else {
                throw RemoteArtifactDownloaderError.urlSessionError(
                    url: request.url!,
                    httpMethod: request.httpMethod!,
                    description: response.description
                )
            }
        } catch {
            if error is RemoteArtifactDownloaderError {
                throw error
            } else {
                throw RemoteArtifactDownloaderError.urlSessionError(
                    url: request.url!,
                    httpMethod:
                    request.httpMethod!,
                    description: error.localizedDescription
                )
            }
        }
    }
}
