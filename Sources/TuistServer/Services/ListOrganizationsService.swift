import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol ListOrganizationsServicing {
    func listOrganizations(
        serverURL: URL
    ) async throws -> [String]
}

enum ListOrganizationsServiceError: FatalError {
    case unknownError(Int)
    case forbidden(String)
    case unauthorized(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .forbidden, .unauthorized:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The organizations could not be listed due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class ListOrganizationsService: ListOrganizationsServicing {
    public init() {}

    public func listOrganizations(
        serverURL: URL
    ) async throws -> [String] {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.listOrganizations(
            .init(
                query: .init()
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(data):
                return data.organizations.map(\.name)
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw ListOrganizationsServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListOrganizationsServiceError.unknownError(statusCode)
        }
    }
}
