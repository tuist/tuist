import Foundation
import Mockable
import TuistSupport

@Mockable
public protocol MultipartUploadGenerateURLBuildsServicing {
    func uploadBuilds(
        _ buildId: String,
        partNumber: Int,
        uploadId: String,
        serverURL: URL
    ) async throws -> String
}

public enum MultipartUploadGenerateURLBuildsServiceError: FatalError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    public var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .notFound, .forbidden, .unauthorized:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The generation of a multi-part upload URL failed due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class MultipartUploadGenerateURLBuildsService: MultipartUploadGenerateURLBuildsServicing {
    public init() {}

    public func uploadBuilds(
        _ buildId: String,
        partNumber: Int,
        uploadId: String,
        serverURL: URL
    ) async throws -> String {
        let client = Client.cloud(serverURL: serverURL)
        let response = try await client.generateBuildsMultipartUploadURL(
            .init(
                path: .init(build_id: buildId),
                body: .json(
                    .init(
                        multipart_upload_part: .init(
                            part_number: partNumber,
                            upload_id: uploadId
                        )
                    )
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(cacheArtifact):
                return cacheArtifact.data.url
            }
        case let .undocumented(statusCode: statusCode, _):
            throw MultipartUploadGenerateURLBuildsServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadGenerateURLBuildsServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw MultipartUploadGenerateURLBuildsServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw MultipartUploadGenerateURLBuildsServiceError.unauthorized(error.message)
            }
        }
    }
}
