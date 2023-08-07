import Foundation
import OpenAPIURLSession
import TuistSupport

public protocol CancelOrganizationInviteServicing {
    func cancelOrganizationInvite(
        organizationName: String,
        email: String,
        serverURL: URL
    ) async throws
}

enum CancelOrganizationInviteServiceError: FatalError {
    case unknownError(Int)
    case notFound(String)
    case unauthorized(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .notFound, .unauthorized:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The invitation could not be cancelled due to an unknown cloud response of \(statusCode)."
        case let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public final class CancelOrganizationInviteService: CancelOrganizationInviteServicing {
    public init() {}

    public func cancelOrganizationInvite(
        organizationName: String,
        email: String,
        serverURL: URL
    ) async throws {
        let client = Client.cloud(serverURL: serverURL)

        let response = try await client.cancelOrganizationInvite(
            .init(
                path: .init(organization_name: organizationName),
                body: .json(.init(invitee_email: email))
            )
        )
        switch response {
        case .noContent:
            // noop
            break
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw CancelOrganizationInviteServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorizedResponse):
            switch unauthorizedResponse.body {
            case let .json(error):
                throw CancelOrganizationInviteServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CancelOrganizationInviteServiceError.unknownError(statusCode)
        }
    }
}
