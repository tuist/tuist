import Foundation
import Mockable
import TuistSupport

@Mockable
public protocol CleanCacheServicing {
    func cleanCache(
        serverURL: URL,
        fullName: String
    ) async throws
}

enum CleanCacheServiceError: FatalError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .notFound, .forbidden, .unauthorized:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The project clean failed due to an unknown cloud response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class CleanCacheService: CleanCacheServicing {
    public init() {}

    public func cleanCache(
        serverURL: URL,
        fullName: String
    ) async throws {
        let client = Client.cloud(serverURL: serverURL)
        let components = fullName.components(separatedBy: "/")

        let response = try await client.cleanCache(
            .init(path: .init(account_name: components[0], project_name: components[1]))
        )

        switch response {
        case .noContent:
            // noop
            break
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw CleanCacheServiceError.notFound(error.message)
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw CleanCacheServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CleanCacheServiceError.unknownError(statusCode)
        }
    }
}
