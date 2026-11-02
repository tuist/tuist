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

enum GetNotificationPreferencesServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The notification preferences could not be fetched due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message), let .notFound(message):
            return message
        }
    }
}

public struct GetNotificationPreferencesService: GetNotificationPreferencesServicing {
    public init() {}

    public func getNotificationPreferences(
        kind: String,
        serverURL: URL
    ) async throws -> ServerNotificationPreferences {
        let client = Client.authenticated(serverURL: serverURL)

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
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw GetNotificationPreferencesServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetNotificationPreferencesServiceError.unknownError(statusCode)
        }
    }
}
