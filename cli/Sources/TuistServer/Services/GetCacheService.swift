#if canImport(TuistCore)
    import Foundation
    import Mockable
    import TuistCore

    @Mockable
    public protocol GetCacheServicing {
        func getCache(
            serverURL: URL,
            projectId: String,
            hash: String,
            name: String,
            cacheCategory: RemoteCacheCategory
        ) async throws -> ServerCacheArtifact
    }

    public enum GetCacheServiceError: LocalizedError, Equatable {
        case unknownError(Int)
        case notFound(String)
        case paymentRequired(String)
        case forbidden(String)
        case unauthorized(String)

        public var errorDescription: String? {
            switch self {
            case let .unknownError(statusCode):
                return
                    "The remote cache could not be used due to an unknown Tuist response of \(statusCode)."
            case let .notFound(message), let .paymentRequired(message), let .forbidden(message),
                 let .unauthorized(message):
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
            name: String,
            cacheCategory: RemoteCacheCategory
        ) async throws -> ServerCacheArtifact {
            let client = Client.authenticated(serverURL: serverURL)

            let response = try await client.downloadCacheArtifact(
                .init(
                    query: .init(
                        cache_category: .init(cacheCategory), project_id: projectId, hash: hash,
                        name: name
                    )
                )
            )

            switch response {
            case let .ok(okResponse):
                switch okResponse.body {
                case let .json(cacheArtifact):
                    return try ServerCacheArtifact(cacheArtifact)
                }
            case let .code402(paymentRequiredResponse):
                switch paymentRequiredResponse.body {
                case let .json(error):
                    throw GetCacheServiceError.paymentRequired(error.message)
                }
            case let .undocumented(statusCode: statusCode, _):
                throw GetCacheServiceError.unknownError(statusCode)
            case let .forbidden(forbiddenResponse):
                switch forbiddenResponse.body {
                case let .json(error):
                    throw GetCacheServiceError.forbidden(error.message)
                }
            case let .notFound(notFound):
                switch notFound.body {
                case let .json(error):
                    throw GetCacheServiceError.notFound(error.message)
                }
            case let .unauthorized(unauthorized):
                switch unauthorized.body {
                case let .json(error):
                    throw GetCacheServiceError.unauthorized(error.message)
                }
            }
        }
    }
#endif
