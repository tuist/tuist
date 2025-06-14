#if canImport(TuistCore)
    import Foundation
    import Mockable
    import TuistCore

    @Mockable
    public protocol MultipartUploadGenerateURLCacheServicing {
        func uploadCache(
            serverURL: URL,
            projectId: String,
            hash: String,
            name: String,
            cacheCategory: RemoteCacheCategory,
            uploadId: String,
            partNumber: Int,
            contentLength: Int
        ) async throws -> String
    }

    public enum MultipartUploadGenerateURLCacheServiceError: LocalizedError, Equatable {
        case unknownError(Int)
        case notFound(String)
        case paymentRequired(String)
        case forbidden(String)
        case unauthorized(String)

        public var errorDescription: String? {
            switch self {
            case let .unknownError(statusCode):
                return
                    "The generation of a multi-part upload URL failed due to an unknown Tuist response of \(statusCode)."
            case let .notFound(message), let .paymentRequired(message), let .forbidden(message),
                 let .unauthorized(message):
                return message
            }
        }
    }

    public final class MultipartUploadGenerateURLCacheService: MultipartUploadGenerateURLCacheServicing {
        public init() {}

        public func uploadCache(
            serverURL: URL,
            projectId: String,
            hash: String,
            name: String,
            cacheCategory: RemoteCacheCategory,
            uploadId: String,
            partNumber: Int,
            contentLength: Int
        ) async throws -> String {
            let client = Client.authenticated(serverURL: serverURL)
            let response = try await client.generateCacheArtifactMultipartUploadURL(
                .init(
                    query: .init(
                        cache_category: .init(cacheCategory),
                        content_length: contentLength,
                        project_id: projectId,
                        hash: hash,
                        part_number: partNumber,
                        upload_id: uploadId,
                        name: name
                    )
                )
            )
            switch response {
            case let .ok(okResponse):
                switch okResponse.body {
                case let .json(cacheArtifact):
                    return cacheArtifact.data.url
                }
            case let .code402(paymentRequiredResponse):
                switch paymentRequiredResponse.body {
                case let .json(error):
                    throw MultipartUploadGenerateURLCacheServiceError.paymentRequired(error.message)
                }
            case let .undocumented(statusCode: statusCode, _):
                throw MultipartUploadGenerateURLCacheServiceError.unknownError(statusCode)
            case let .forbidden(forbiddenResponse):
                switch forbiddenResponse.body {
                case let .json(error):
                    throw MultipartUploadGenerateURLCacheServiceError.forbidden(error.message)
                }
            case let .notFound(notFoundResponse):
                switch notFoundResponse.body {
                case let .json(error):
                    throw MultipartUploadGenerateURLCacheServiceError.notFound(error.message)
                }
            case let .unauthorized(unauthorized):
                switch unauthorized.body {
                case let .json(error):
                    throw MultipartUploadGenerateURLCacheServiceError.unauthorized(error.message)
                }
            }
        }
    }
#endif
