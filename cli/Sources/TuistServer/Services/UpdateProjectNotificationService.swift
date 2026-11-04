import Foundation
import Mockable
import OpenAPIRuntime

@Mockable
public protocol UpdateProjectNotificationServicing: Sendable {
    /// Overrides a notification kind for one project, or follows its account again with `.default`, and returns
    /// the refreshed preferences.
    func updateProjectNotificationPreference(
        kind: String,
        accountHandle: String,
        projectHandle: String,
        setting: ServerNotificationPreferences.ProjectSetting,
        serverURL: URL
    ) async throws -> ServerNotificationPreferences
}

enum UpdateProjectNotificationServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case tooManyRequests(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The project notification preference could not be updated due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message), let .notFound(message), let .tooManyRequests(message):
            return message
        }
    }
}

public struct UpdateProjectNotificationService: UpdateProjectNotificationServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func updateProjectNotificationPreference(
        kind: String,
        accountHandle: String,
        projectHandle: String,
        setting: ServerNotificationPreferences.ProjectSetting,
        serverURL: URL
    ) async throws -> ServerNotificationPreferences {
        let client = makeClient(serverURL)

        let response = try await client.updateProjectNotificationPreference(
            .init(
                path: .init(kind: kind, account_handle: accountHandle, project_handle: projectHandle),
                body: .json(.init(setting: settingPayload(setting)))
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
                throw UpdateProjectNotificationServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw UpdateProjectNotificationServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw UpdateProjectNotificationServiceError.notFound(error.message)
            }
        case let .tooManyRequests(tooManyRequests):
            switch tooManyRequests.body {
            case let .json(error):
                throw UpdateProjectNotificationServiceError.tooManyRequests(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UpdateProjectNotificationServiceError.unknownError(statusCode)
        }
    }

    private func settingPayload(
        _ setting: ServerNotificationPreferences.ProjectSetting
    ) -> Operations.updateProjectNotificationPreference.Input.Body.jsonPayload.settingPayload {
        switch setting {
        case .default: ._default
        case .on: .on
        case .off: .off
        }
    }
}
