import Foundation
import OpenAPIURLSession

public protocol DeleteOrganizationServicing {
    func deleteOrganization(
        name: String,
        serverURL: URL
    ) async throws
}

enum DeleteOrganizationServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The organization could not be deleted due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .unauthorized(message), let .notFound(message):
            return message
        }
    }
}

public final class DeleteOrganizationService: DeleteOrganizationServicing {
    public init() {}

    public func deleteOrganization(
        name: String,
        serverURL: URL
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.deleteOrganization(
            .init(
                path: .init(
                    organization_name: name
                )
            )
        )
        switch response {
        case .noContent:
            // noop
            break
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw DeleteOrganizationServiceError.unknownError(statusCode)
        }
    }
}
