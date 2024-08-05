import Foundation
import OpenAPIURLSession
import TuistSupport

public protocol RemoveOrganizationMemberServicing {
    func removeOrganizationMember(
        organizationName: String,
        username: String,
        serverURL: URL
    ) async throws
}

enum RemoveOrganizationMemberServiceError: FatalError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case badRequest(String)
    case unauthorized(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .notFound, .forbidden, .badRequest, .unauthorized:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The member could not be removed due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .badRequest(message), let .unauthorized(message):
            return message
        }
    }
}

public final class RemoveOrganizationMemberService: RemoveOrganizationMemberServicing {
    public init() {}

    public func removeOrganizationMember(
        organizationName: String,
        username: String,
        serverURL: URL
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.removeOrganizationMember(
            .init(
                path: .init(
                    organization_name: organizationName,
                    user_name: username
                )
            )
        )
        switch response {
        case .noContent:
            // noop
            break
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw RemoveOrganizationMemberServiceError.notFound(error.message)
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw RemoveOrganizationMemberServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw RemoveOrganizationMemberServiceError.unknownError(statusCode)
        case let .badRequest(badRequestResponse):
            switch badRequestResponse.body {
            case let .json(error):
                throw RemoveOrganizationMemberServiceError.badRequest(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        }
    }
}
