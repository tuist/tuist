import Foundation
import TuistCloudSchema
import TuistSupport

public protocol CleanCacheServicing {
    func cleanCache(
        serverURL: URL,
        fullName: String
    ) async throws
}

enum CleanCacheServiceError: FatalError {
    case unknownError(Int)
    case notFound(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .notFound:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The project clean failed due to an unknown cloud response of \(statusCode)."
        case let .notFound(message):
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
        
        let response = try await client.cleanCache(
            .init(path: .init(full_name: fullName))
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
        case let .undocumented(statusCode: statusCode, _):
            throw CleanCacheServiceError.unknownError(statusCode)
        }
    }
}
