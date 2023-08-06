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
            return "The member could not be removed due to an unknown cloud response of \(statusCode)."
        case let .notFound(message), let .unauthorized(message):
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
        let client = Client.cloud(serverURL: serverURL)

        let response = try await client.removeOrganizationMember(
            .init(
                path: .init(
                    organization_name: organizationName,
                    username: username
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
        case let .unauthorized(unauthorizedResponse):
            switch unauthorizedResponse.body {
            case let .json(error):
                throw RemoveOrganizationMemberServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw RemoveOrganizationMemberServiceError.unknownError(statusCode)
        }
    }
}
