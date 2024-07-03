import Foundation
import Mockable
import TuistCore
import TuistSupport

@Mockable
public protocol MultipartUploadStartCacheServicing {
    func uploadCache(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String,
        cacheCategory: RemoteCacheCategory
    ) async throws -> String
}

public enum MultipartUploadStartCacheServiceError: FatalError, Equatable {
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
            return "The remote cache artifact could not be uploaded due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .paymentRequired(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class MultipartUploadStartCacheService: MultipartUploadStartCacheServicing {
    public init() {}

    public func uploadCache(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String,
        cacheCategory: RemoteCacheCategory
    ) async throws -> String {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.startCacheArtifactMultipartUpload(.init(query: .init(
            cache_category: .init(cacheCategory),
            project_id: projectId,
            hash: hash,
            name: name
        )))
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(cacheArtifact):
                return cacheArtifact.data.upload_id
            }
        case let .paymentRequired(paymentRequiredResponse):
            switch paymentRequiredResponse.body {
            case let .json(error):
                throw MultipartUploadStartCacheServiceError.paymentRequired(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw MultipartUploadStartCacheServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadStartCacheServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw MultipartUploadStartCacheServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        }
    }
}
