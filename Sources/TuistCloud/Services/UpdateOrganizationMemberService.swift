import Foundation
import OpenAPIURLSession
import TuistSupport

public protocol UpdateOrganizationMemberServicing {
    func updateOrganizationMember(
        organizationName: String,
        username: String,
        role: CloudOrganization.Member.Role,
        serverURL: URL
    ) async throws -> CloudOrganization.Member
}

enum UpdateOrganizationMemberServiceError: FatalError {
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
            return "The member could not be updated due to an unknown cloud response of \(statusCode)."
        case let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public final class UpdateOrganizationMemberService: UpdateOrganizationMemberServicing {
    public init() {}

    public func updateOrganizationMember(
        organizationName: String,
        username: String,
        role: CloudOrganization.Member.Role,
        serverURL: URL
    ) async throws -> CloudOrganization.Member {
        let client = Client.cloud(serverURL: serverURL)

        let response = try await client.updateOrganizationMember(
            .init(
                path: .init(
                    organization_name: organizationName,
                    username: username
                ),
                body: .json(.init(role: .init(stringLiteral: role.rawValue)))
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(organizationMember):
                return CloudOrganization.Member(organizationMember)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw UpdateOrganizationMemberServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorizedResponse):
            switch unauthorizedResponse.body {
            case let .json(error):
                throw UpdateOrganizationMemberServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UpdateOrganizationMemberServiceError.unknownError(statusCode)
        }
    }
}
