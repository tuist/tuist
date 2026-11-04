import Foundation
import Mockable
import OpenAPIRuntime

@Mockable
public protocol GetNotificationPreferencesServicing: Sendable {
    func getNotificationPreferences(
        kind: String,
        serverURL: URL
    ) async throws -> ServerNotificationPreferences
}

public enum GetNotificationPreferencesServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    /// The server predates notification preferences or doesn't offer this kind yet.
    case unsupported

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The notification preferences could not be fetched due to an unknown Tuist response of \(statusCode)."
        case .unsupported:
            return "This Tuist server doesn't offer these notifications yet. Ask its administrator to update it."
        case let .unauthorized(message), let .forbidden(message):
            return message
        }
    }
}

public struct GetNotificationPreferencesService: GetNotificationPreferencesServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func getNotificationPreferences(
        kind: String,
        serverURL: URL
    ) async throws -> ServerNotificationPreferences {
        let client = makeClient(serverURL)

        let response = try await client.getNotificationPreferences(.init(path: .init(kind: kind)))
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return ServerNotificationPreferences(json)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GetNotificationPreferencesServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetNotificationPreferencesServiceError.forbidden(error.message)
            }
        // Both a server without these routes and one that doesn't know the kind answer 404.
        case .notFound, .undocumented(statusCode: 404, _):
            throw GetNotificationPreferencesServiceError.unsupported
        case let .undocumented(statusCode: statusCode, _):
            throw GetNotificationPreferencesServiceError.unknownError(statusCode)
        }
    }
}
