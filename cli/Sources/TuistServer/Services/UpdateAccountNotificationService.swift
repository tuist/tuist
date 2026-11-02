import Foundation
import Mockable
import OpenAPIRuntime

@Mockable
public protocol UpdateAccountNotificationServicing: Sendable {
    /// Turns a notification kind on or off for one of the user's accounts and returns the refreshed preferences.
    func updateAccountNotificationPreference(
        kind: String,
        accountHandle: String,
        enabled: Bool,
        serverURL: URL
    ) async throws -> ServerNotificationPreferences
}

enum UpdateAccountNotificationServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The notification preference could not be updated due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message), let .notFound(message):
            return message
        }
    }
}

public struct UpdateAccountNotificationService: UpdateAccountNotificationServicing {
    public init() {}

    public func updateAccountNotificationPreference(
        kind: String,
        accountHandle: String,
        enabled: Bool,
        serverURL: URL
    ) async throws -> ServerNotificationPreferences {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.updateAccountNotificationPreference(
            .init(
                path: .init(kind: kind, account_handle: accountHandle),
                body: .json(.init(enabled: enabled))
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return ServerNotificationPreferences(json)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw UpdateAccountNotificationServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw UpdateAccountNotificationServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw UpdateAccountNotificationServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UpdateAccountNotificationServiceError.unknownError(statusCode)
        }
    }
}
