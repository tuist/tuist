import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol GetOrganizationServicing {
    func getOrganization(
        organizationName: String,
        serverURL: URL
    ) async throws -> CloudOrganization
}

enum GetOrganizationServiceError: FatalError {
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
            return "We could not get the organization due to an unknown cloud response of \(statusCode)."
        case let .forbidden(message), let .notFound(message):
            return message
        }
    }
}

public final class GetOrganizationService: GetOrganizationServicing {
    public init() {}

    public func getOrganization(
        organizationName: String,
        serverURL: URL
    ) async throws -> CloudOrganization {
        let client = Client.cloud(serverURL: serverURL)

        let response = try await client.showOrganization(
            .init(
                path: .init(
                    organization_name: organizationName
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(project):
                return CloudOrganization(project)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw GetOrganizationServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetOrganizationServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetOrganizationServiceError.unknownError(statusCode)
        }
    }
}
