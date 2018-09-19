import Foundation
import TuistCore
import Utility

protocol GitHubClienting: AnyObject {
    func releases() throws -> [Release]
    func release(tag: String) throws -> Release
    func getContent(ref: String, path: String) throws -> String
}

enum GitHubClientError: FatalError {
    case sessionError(Error)
    case missingData
    case decodingError(Error)
    case invalidResponse

    var type: ErrorType {
        switch self {
        case .sessionError: return .abort
        case .missingData: return .abort
        case .decodingError: return .bug
        case .invalidResponse: return .bug
        }
    }

    var description: String {
        switch self {
        case let .sessionError(error):
            return "Session error: \(error.localizedDescription)"
        case .missingData:
            return "No data received from the GitHub API"
        case let .decodingError(error):
            return "Error decoding JSON from API: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received an invalid response from the GitHub API"
        }
    }
}

class GitHubClient: GitHubClienting {
    // MARK: - Attributes

    let sessionScheduler: URLSessionScheduling
    let requestFactory: GitHubRequestsFactory
    let decoder: JSONDecoder

    // MARK: - Init

    init(sessionScheduler: URLSessionScheduling = URLSessionScheduler(),
         requestFactory: GitHubRequestsFactory = GitHubRequestsFactory(),
         decoder: JSONDecoder = JSONDecoder()) {
        self.sessionScheduler = sessionScheduler
        self.requestFactory = requestFactory
        self.decoder = decoder
    }

    // MARK: - GitHubClienting

    func execute(request: URLRequest) throws -> Data {
        let response = sessionScheduler.schedule(request: request)
        if let error = response.error {
            throw GitHubClientError.sessionError(error)
        } else if response.data == nil {
            throw GitHubClientError.missingData
        } else {
            return response.data!
        }
    }

    func releases() throws -> [Release] {
        let data = try execute(request: requestFactory.releases())
        do {
            return try decoder.decode([Release].self, from: data)
        } catch {
            throw GitHubClientError.decodingError(error)
        }
    }

    func release(tag: String) throws -> Release {
        let data = try execute(request: requestFactory.release(tag: tag))
        do {
            return try decoder.decode(Release.self, from: data)
        } catch {
            throw GitHubClientError.decodingError(error)
        }
    }

    func getContent(ref: String, path: String) throws -> String {
        let data = try execute(request: requestFactory.getContent(ref: ref, path: path))
        do {
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                let content = json["content"] as? String,
                let base64Data = Data(base64Encoded: content),
                let decodedContent = String(data: base64Data, encoding: .utf8) else {
                throw GitHubClientError.invalidResponse
            }
            return decodedContent
        } catch {
            throw GitHubClientError.decodingError(error)
        }
    }
}
