import Foundation
import Mockable
import TuistCore
import TuistSupport

@Mockable
public protocol CacheExistsServicing {
    func cacheExists(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String,
        cacheCategory: RemoteCacheCategory
    ) async throws -> Bool
}

public enum CacheExistsServiceError: FatalError, Equatable {
    case unknownError(Int)
    case paymentRequired(String)
    case forbidden(String)
    case unauthorized(String)

    public var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .paymentRequired, .forbidden, .unauthorized:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The remote cache could not be used due to an unknown Tuist response of \(statusCode)."
        case let .paymentRequired(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class CacheExistsService: CacheExistsServicing {
    public init() {}

    public func cacheExists(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String,
        cacheCategory: RemoteCacheCategory
    ) async throws -> Bool {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.cacheArtifactExists(
            .init(query: .init(cache_category: .init(cacheCategory), project_id: projectId, hash: hash, name: name))
        )

        switch response {
        case .ok:
            return true
        case .notFound:
            return false
        case let .paymentRequired(paymentRequiredResponse):
            switch paymentRequiredResponse.body {
            case let .json(error):
                throw CacheExistsServiceError.paymentRequired(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CacheExistsServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw CacheExistsServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        }
    }
}
