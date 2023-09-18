import Foundation
import OpenAPIURLSession
import TuistSupport

public protocol ListOrganizationsServicing {
    func listOrganizations(
        serverURL: URL
    ) async throws -> [CloudOrganization]
}

enum ListOrganizationsServiceError: FatalError {
    case unknownError(Int)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The organizations could not be listed due to an unknown cloud response of \(statusCode)."
        }
    }
}

public final class ListOrganizationsService: ListOrganizationsServicing {
    public init() {}

    public func listOrganizations(
        serverURL: URL
    ) async throws -> [CloudOrganization] {
        let client = Client.cloud(serverURL: serverURL)

        let response = try await client.listOrganizations(
            .init()
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json.organizations.map(CloudOrganization.init)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListOrganizationsServiceError.unknownError(statusCode)
        }
    }
}
