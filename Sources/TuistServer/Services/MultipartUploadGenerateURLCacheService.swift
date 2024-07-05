import Foundation
import Mockable
import TuistCore
import TuistSupport

@Mockable
public protocol MultipartUploadGenerateURLCacheServicing {
    func uploadCache(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String,
        cacheCategory: RemoteCacheCategory,
        uploadId: String,
        partNumber: Int
    ) async throws -> String
}

public enum MultipartUploadGenerateURLCacheServiceError: FatalError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case paymentRequired(String)
    case forbidden(String)
    case unauthorized(String)

    public var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .notFound, .paymentRequired, .forbidden, .unauthorized:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The generation of a multi-part upload URL failed due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .paymentRequired(message), let .forbidden(message), let .unauthorized(message):
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
        partNumber: Int
    ) async throws -> String {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.generateCacheArtifactMultipartUploadURL(.init(query: .init(
            cache_category: .init(cacheCategory),
            project_id: projectId,
            hash: hash,
            part_number: partNumber,
            upload_id: uploadId,
            name: name
        )))
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(cacheArtifact):
                return cacheArtifact.data.url
            }
        case let .paymentRequired(paymentRequiredResponse):
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
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        }
    }
}
