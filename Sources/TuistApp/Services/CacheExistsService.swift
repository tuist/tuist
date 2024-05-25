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
        cacheCategory: CacheCategory.App
    ) async throws
}

public enum CacheExistsServiceError: FatalError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case paymentRequired(String)
    case forbidden(String)

    public var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .notFound, .paymentRequired, .forbidden:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The remote cache could not be used due to an unknown Tuist Cloud response of \(statusCode)."
        case let .notFound(message), let .paymentRequired(message), let .forbidden(message):
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
        cacheCategory: CacheCategory.App
    ) async throws {
        let client = Client.cloud(serverURL: serverURL)

        let response = try await client.cacheArtifactExists(
            .init(query: .init(cache_category: .init(cacheCategory), project_id: projectId, hash: hash, name: name))
        )

        switch response {
        case .ok:
            // noop
            break
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(body):
                throw CacheExistsServiceError.notFound(body.error?.first?.message ?? "The remote cache artifact does not exist")
            }
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
        }
    }
}
