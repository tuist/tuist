import Foundation
import Mockable
import OpenAPIRuntime

@Mockable
public protocol ListFeatureFlagsServicing: Sendable {
    /// The names of the feature flags enabled for the signed-in user. Servers that predate feature flags enable none.
    func listFeatureFlags(serverURL: URL) async throws -> Set<String>
}

public enum ListFeatureFlagsServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The feature flags could not be fetched due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message):
            return message
        }
    }
}

public struct ListFeatureFlagsService: ListFeatureFlagsServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func listFeatureFlags(serverURL: URL) async throws -> Set<String> {
        let response = try await makeClient(serverURL).listFeatureFlags(.init())
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return Set(json.enabled)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw ListFeatureFlagsServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw ListFeatureFlagsServiceError.forbidden(error.message)
            }
        case .undocumented(statusCode: 404, _):
            return []
        case let .undocumented(statusCode: statusCode, _):
            throw ListFeatureFlagsServiceError.unknownError(statusCode)
        }
    }
}
