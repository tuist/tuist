import Foundation
import OpenAPIURLSession
import TuistSupport

public protocol CreateOrganizationInviteServicing {
    func createOrganizationInvite(
        organizationName: String,
        email: String,
        serverURL: URL
    ) async throws -> CloudInvitation
}

enum CreateOrganizationInviteServiceError: FatalError {
    case unknownError(Int)
    case notFound(String)
    case unauthorized(String)
    case badRequest(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .notFound, .unauthorized, .badRequest:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The user could not be invited due to an unknown cloud response of \(statusCode)."
        case let .notFound(message), let .unauthorized(message), let .badRequest(message):
            return message
        }
    }
}

public final class CreateOrganizationInviteService: CreateOrganizationInviteServicing {
    public init() {}

    public func createOrganizationInvite(
        organizationName: String,
        email: String,
        serverURL: URL
    ) async throws -> CloudInvitation {
        let client = Client.cloud(serverURL: serverURL)

        let response = try await client.createOrganizationInvite(
            .init(
                path: .init(organization_name: organizationName),
                body: .json(.init(invitee_email: email))
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(invitation):
                return CloudInvitation(invitation)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw CreateOrganizationInviteServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorizedResponse):
            switch unauthorizedResponse.body {
            case let .json(error):
                throw CreateOrganizationInviteServiceError.unauthorized(error.message)
            }
        case let .badRequest(badRequestResponse):
            switch badRequestResponse.body {
            case let .json(error):
                throw CreateOrganizationInviteServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CreateOrganizationInviteServiceError.unknownError(statusCode)
        }
    }
}
