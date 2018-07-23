import Foundation
import TuistCore
import Utility

protocol GitHubClienting: AnyObject {
    func execute(request: URLRequest) throws -> Any
}

/// GitHub client error.
///
/// - sessionError: when URLSession throws an error.
/// - missingData: when the request doesn't return any data.
/// - decodingError: when there's an error decoding the API response.
enum GitHubClientError: FatalError {
    case sessionError(Error)
    case missingData
    case decodingError(Error)

    var type: ErrorType {
        switch self {
        case .sessionError: return .abort
        case .missingData: return .abort
        case .decodingError: return .bug
        }
    }

    var description: String {
        switch self {
        case let .sessionError(error):
            return "Session error: \(error.localizedDescription)."
        case .missingData:
            return "No data received from the GitHub API."
        case let .decodingError(error):
            return "Error decoding JSON from API: \(error.localizedDescription)"
        }
    }
}

/// GitHub Client.
class GitHubClient: GitHubClienting {
    /// Session scheduler.
    let sessionScheduler: URLSessionScheduling

    init(sessionScheduler: URLSessionScheduling = URLSessionScheduler()) {
        self.sessionScheduler = sessionScheduler
    }

    /// Executes a request against the GitHub API.
    ///
    /// - Parameters:
    ///   - path: request path.
    ///   - method: request HTTP method.
    /// - Returns: API json response.
    /// - Throws: if the request fails.
    func execute(request: URLRequest) throws -> Any {
        let response = sessionScheduler.schedule(request: request)
        if let error = response.error {
            throw GitHubClientError.sessionError(error)
        } else if response.data == nil {
            throw GitHubClientError.missingData
        } else {
            do {
                return try JSONSerialization.jsonObject(with: response.data!, options: [])
            } catch {
                throw GitHubClientError.decodingError(error)
            }
        }
    }
}
