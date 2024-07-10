import Foundation
import Mockable
import OpenAPIRuntime
import TuistCore
import TuistSupport

@Mockable
public protocol MultipartUploadCompleteCacheServicing {
    func uploadCache(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String,
        cacheCategory: RemoteCacheCategory,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)]
    ) async throws
}

public enum MultipartUploadCompleteCacheServiceError: FatalError, Equatable {
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
            return "The multi-part upload could not get completed due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .paymentRequired(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class MultipartUploadCompleteCacheService: MultipartUploadCompleteCacheServicing {
    public init() {}

    public func uploadCache(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String,
        cacheCategory: RemoteCacheCategory,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)]
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.completeCacheArtifactMultipartUpload(.init(query: .init(
            cache_category: .init(cacheCategory),
            project_id: projectId,
            hash: hash,
            upload_id: uploadId,
            name: name
        ), body: .json(.init(parts: parts.map { .init(etag: $0.etag, part_number: $0.partNumber) }))))
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case .json:
                return
            }
        case let .paymentRequired(paymentRequiredResponse):
            switch paymentRequiredResponse.body {
            case let .json(error):
                throw MultipartUploadCompleteCacheServiceError.paymentRequired(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw MultipartUploadCompleteCacheServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadCompleteCacheServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw MultipartUploadCompleteCacheServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        }
    }
}
