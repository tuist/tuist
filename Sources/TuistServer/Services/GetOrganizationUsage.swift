import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol GetOrganizationUsageServicing {
    func getOrganizationUsage(
        organizationName: String,
        serverURL: URL
    ) async throws -> CloudOrganizationUsage
}

enum GetOrganizationUsageServiceError: FatalError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .forbidden, .notFound:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "We could not get the OrganizationUsage due to an unknown cloud response of \(statusCode)."
        case let .forbidden(message), let .notFound(message):
            return message
        }
    }
}

public final class GetOrganizationUsageService: GetOrganizationUsageServicing {
    public init() {}

    public func getOrganizationUsage(
        organizationName: String,
        serverURL: URL
    ) async throws -> CloudOrganizationUsage {
        let client = Client.cloud(serverURL: serverURL)

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
                return CloudOrganizationUsage(organizationUsage)
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
        case let .undocumented(statusCode: statusCode, _):
            throw GetOrganizationUsageServiceError.unknownError(statusCode)
        }
    }
}
