import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol CreateOrganizationServicing {
    func createOrganization(
        name: String,
        serverURL: URL
    ) async throws -> ServerOrganization
}

enum CreateOrganizationServiceError: LocalizedError {
    case unknownError(Int)
    case badRequest(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The organization could not be created due to an unknown Tuist response of \(statusCode)."
        case let .badRequest(message):
            return message
        }
    }
}

public final class CreateOrganizationService: CreateOrganizationServicing {
    public init() {}

    public func createOrganization(
        name: String,
        serverURL: URL
    ) async throws -> ServerOrganization {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.createOrganization(
            .init(
                body: .json(
                    .init(
                        name: name
                    )
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(organization):
                return ServerOrganization(organization)
            }
        case let .badRequest(badRequestResponse):
            switch badRequestResponse.body {
            case let .json(error):
                throw CreateOrganizationServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CreateOrganizationServiceError.unknownError(statusCode)
        }
    }
}
