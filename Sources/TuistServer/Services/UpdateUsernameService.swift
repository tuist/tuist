import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol UpdateUsernameServicing {
    func updateUsername(
        serverURL: URL,
        name: String
    ) async throws -> String?
}

enum UpdateUsernameServiceError: FatalError {
    case unknownError(Int)
    case badRequest(String)
    case unauthorized(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .badRequest, .unauthorized:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "We could not update the account due to an unknown Tuist response of \(statusCode)."
        case let .badRequest(message), let .unauthorized(message):
            return message
        }
    }
}

public final class UpdateUsernameService: UpdateUsernameServicing {
    public init() {}

    public func updateUsername(
        serverURL: URL,
        name: String
    ) async throws -> String? {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.changeName(
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
            return name;
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw UpdateUsernameServiceError.unauthorized(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw UpdateUsernameServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UpdateUsernameServiceError.unknownError(statusCode)
        }
    }
}
