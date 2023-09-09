import Foundation
import OpenAPIURLSession
import TuistSupport

public protocol CreateOrganizationServicing {
    func createOrganization(
        name: String,
        serverURL: URL
    ) async throws -> CloudOrganization
}

enum CreateOrganizationServiceError: FatalError {
    case unknownError(Int)
    case badRequest(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .badRequest:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The organization could not be created due to an unknown cloud response of \(statusCode)."
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
    ) async throws -> CloudOrganization {
        let client = Client.cloud(serverURL: serverURL)

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
                return CloudOrganization(organization)
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
