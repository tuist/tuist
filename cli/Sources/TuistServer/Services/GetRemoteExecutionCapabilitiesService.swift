import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Mockable
import TuistHTTP

/// The executor endpoint and immutable execution image the server currently
/// advertises for a project. The image changes with every template rollout, so
/// callers fetch it each time instead of persisting it.
public struct RemoteExecutionCapabilities: Equatable, Sendable {
    public let endpoint: String
    public let image: String

    public init(endpoint: String, image: String) {
        self.endpoint = endpoint
        self.image = image
    }
}

@Mockable
public protocol GetRemoteExecutionCapabilitiesServicing: Sendable {
    func getCapabilities(
        serverURL: URL,
        accountHandle: String,
        projectHandle: String,
        token: String
    ) async throws -> RemoteExecutionCapabilities
}

public enum GetRemoteExecutionCapabilitiesServiceError: LocalizedError, Equatable {
    case notEnabled
    case unavailable
    case invalidResponse
    case unknownError(Int)

    public var errorDescription: String? {
        switch self {
        case .notEnabled:
            return "Remote execution is not enabled for this project."
        case .unavailable:
            return "No remote execution capacity is available."
        case .invalidResponse:
            return "The server returned invalid remote execution capabilities."
        case let .unknownError(statusCode):
            return "Failed to retrieve remote execution capabilities due to an unknown server response of \(statusCode)."
        }
    }
}

extension GetRemoteExecutionCapabilitiesServiceError: HTTPStatusCodeError {
    public var httpStatusCode: Int {
        switch self {
        case .notEnabled: return 403
        case .unavailable: return 503
        case .invalidResponse: return 200
        case let .unknownError(status): return status
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .invalidResponse: return false
        default: return !HTTPRetryPolicy.isPermanentClientError(statusCode: httpStatusCode)
        }
    }
}

/// Reads `GET /api/remote-execution/:account/:project/capabilities`, which
/// authenticates with the project's scoped cache token rather than the user's
/// session.
public struct GetRemoteExecutionCapabilitiesService: GetRemoteExecutionCapabilitiesServicing {
    private let perform: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init() {
        self.init(perform: { try await URLSession.tuistDefault.data(for: $0) })
    }

    init(perform: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.perform = perform
    }

    public func getCapabilities(
        serverURL: URL,
        accountHandle: String,
        projectHandle: String,
        token: String
    ) async throws -> RemoteExecutionCapabilities {
        let url = serverURL
            .appendingPathComponent("api")
            .appendingPathComponent("remote-execution")
            .appendingPathComponent(accountHandle)
            .appendingPathComponent(projectHandle)
            .appendingPathComponent("capabilities")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.addRequestIDHeader()

        return try await HTTPRetryPolicy().run { [perform, request] in
            let (data, response) = try await perform(request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch statusCode {
            case 200:
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let endpoint = json["endpoint"] as? String,
                      let image = json["image"] as? String
                else { throw GetRemoteExecutionCapabilitiesServiceError.invalidResponse }
                return RemoteExecutionCapabilities(endpoint: endpoint, image: image)
            case 403:
                throw GetRemoteExecutionCapabilitiesServiceError.notEnabled
            case 503:
                throw GetRemoteExecutionCapabilitiesServiceError.unavailable
            default:
                throw GetRemoteExecutionCapabilitiesServiceError.unknownError(statusCode)
            }
        }
    }
}
