import Foundation
import Mockable
import OpenAPIRuntime

@Mockable
public protocol CreateOrganizationInviteServicing {
    func createOrganizationInvite(
        organizationName: String,
        email: String,
        role: Operations.createInvitation.Input.Body.jsonPayload.rolePayload?,
        serverURL: URL
    ) async throws -> ServerInvitation
}

enum CreateOrganizationInviteServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case badRequest(String)
    case unauthorized(String)
    case tooManyRequests(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The user could not be invited due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .badRequest(message), let .unauthorized(message),
             let .tooManyRequests(message):
            return message
        }
    }
}

public struct CreateOrganizationInviteService: CreateOrganizationInviteServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func createOrganizationInvite(
        organizationName: String,
        email: String,
        role: Operations.createInvitation.Input.Body.jsonPayload.rolePayload?,
        serverURL: URL
    ) async throws -> ServerInvitation {
        let client = makeClient(serverURL)

        let response = try await client.createInvitation(
            .init(
                path: .init(organization_name: organizationName),
                body: .json(.init(invitee_email: email, role: role))
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(invitation):
                return ServerInvitation(invitation)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw CreateOrganizationInviteServiceError.notFound(error.message)
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw CreateOrganizationInviteServiceError.forbidden(error.message)
            }
        case let .badRequest(badRequestResponse):
            switch badRequestResponse.body {
            case let .json(error):
                throw CreateOrganizationInviteServiceError.badRequest(error.message)
            }
        case let .tooManyRequests(response):
            switch response.body {
            case let .json(error):
                throw CreateOrganizationInviteServiceError.tooManyRequests(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CreateOrganizationInviteServiceError.unknownError(statusCode)
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw CreateOrganizationInviteServiceError.unauthorized(error.message)
            }
        }
    }
}
