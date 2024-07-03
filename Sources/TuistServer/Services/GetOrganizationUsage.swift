import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol GetOrganizationUsageServicing {
    func getOrganizationUsage(
        organizationName: String,
        serverURL: URL
    ) async throws -> ServerOrganizationUsage
}

enum GetOrganizationUsageServiceError: FatalError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .forbidden, .notFound, .unauthorized:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "We could not get the OrganizationUsage due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public final class GetOrganizationUsageService: GetOrganizationUsageServicing {
    public init() {}

    public func getOrganizationUsage(
        organizationName: String,
        serverURL: URL
    ) async throws -> ServerOrganizationUsage {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.showOrganizationUsage(
            .init(
                path: .init(
                    organization_name: organizationName
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(organizationUsage):
                return ServerOrganizationUsage(organizationUsage)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw GetOrganizationUsageServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetOrganizationUsageServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetOrganizationUsageServiceError.unknownError(statusCode)
        }
    }
}
