import Foundation
import TuistSupport

public protocol GetCacheServicing {
    func getCache(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String
    ) async throws -> CloudCacheArtifact
}

public enum GetCacheServiceError: FatalError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case paymentRequired(String)
    case unauthorized(String)

    public var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .notFound, .paymentRequired, .unauthorized:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The remote cache could not be used due to an unknown Tuist Cloud response of \(statusCode)."
        case let .notFound(message), let .paymentRequired(message), let .unauthorized(message):
            return message
        }
    }
}

public final class GetCacheService: GetCacheServicing {
    public init() {}

    public func getCache(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String
    ) async throws -> CloudCacheArtifact {
        let client = Client.cloud(serverURL: serverURL)

        let response = try await client.getCache(
            .init(query: .init(project_id: projectId, hash: hash, name: name))
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(cacheArtifact):
                return try CloudCacheArtifact(cacheArtifact)
            }
        case let .paymentRequired(paymentRequiredResponse):
            switch paymentRequiredResponse.body {
            case let .json(error):
                throw GetCacheServiceError.paymentRequired(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetCacheServiceError.unknownError(statusCode)
        case let .unauthorized(unauthorizedResponse):
            switch unauthorizedResponse.body {
            case let .json(error):
                throw GetCacheServiceError.unauthorized(error.message)
            }
        }
    }
}
