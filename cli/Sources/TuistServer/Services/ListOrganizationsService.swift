import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol ListOrganizationsServicing {
    func listOrganizations(
        serverURL: URL
    ) async throws -> [String]
}

enum ListOrganizationsServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case unauthorized(String)

    var errorDescription: String? {
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

        let response = try await client.listOrganizations()
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
                throw ListOrganizationsServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListOrganizationsServiceError.unknownError(statusCode)
        }
    }
}
