import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol UpdateOrganizationServicing {
    func updateOrganization(
        organizationName: String,
        serverURL: URL,
        ssoOrganization: SSOOrganization?
    ) async throws -> CloudOrganization
}

enum UpdateOrganizationServiceError: FatalError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case badRequest(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .forbidden, .notFound, .badRequest:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "We could not get the organization due to an unknown cloud response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .badRequest(message):
            return message
        }
    }
}

public final class UpdateOrganizationService: UpdateOrganizationServicing {
    public init() {}

    public func updateOrganization(
        organizationName: String,
        serverURL: URL,
        ssoOrganization: SSOOrganization?
    ) async throws -> CloudOrganization {
        let client = Client.cloud(serverURL: serverURL)
        let ssoProvider: Operations.updateOrganization
            .Input.Body.jsonPayload.sso_providerPayload
        let ssoOrganizationId: String?

        if let ssoOrganization {
            switch ssoOrganization {
            case let .google(organizationId):
                ssoProvider = .google
                ssoOrganizationId = organizationId
            }
        } else {
            ssoOrganizationId = nil
            ssoProvider = .none
        }

        let response = try await client.updateOrganization(
            .init(
                path: .init(
                    organization_name: organizationName
                ),
                body: .json(
                    .init(
                        sso_organization_id: ssoOrganizationId,
                        sso_provider: ssoProvider
                    )
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
                throw UpdateOrganizationServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw UpdateOrganizationServiceError.forbidden(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw UpdateOrganizationServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UpdateOrganizationServiceError.unknownError(statusCode)
        }
    }
}
