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
    case forbidden(String)
    case unauthorized(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .notFound, .forbidden, .unauthorized:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The invitation could not be cancelled due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message):
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
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.cancelInvitation(
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
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw CancelOrganizationInviteServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CancelOrganizationInviteServiceError.unknownError(statusCode)
        }
    }
}
