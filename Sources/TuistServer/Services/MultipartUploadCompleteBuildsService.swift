import Foundation
import Mockable
import OpenAPIRuntime
import TuistSupport

@Mockable
public protocol MultipartUploadCompleteBuildsServicing {
    func uploadBuildsArtifact(
        _ buildId: String,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)],
        serverURL: URL
    ) async throws
}

public enum MultipartUploadCompleteBuildsServiceError: FatalError, Equatable {
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
            return "The multi-part upload could not get completed due to an unknown Tuist Cloud response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class MultipartUploadCompleteBuildsService: MultipartUploadCompleteBuildsServicing {
    public init() {}

    public func uploadBuildsArtifact(
        _ buildId: String,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)],
        serverURL: URL
    ) async throws {
        let client = Client.cloud(serverURL: serverURL)
        let response = try await client.completeBuildsMultipartUpload(
            .init(
                path: .init(build_id: buildId),
                body: .json(
                    .init(
                        multipart_upload_parts: .init(
                            parts: parts
                                .map { .init(etag: $0.etag, part_number: $0.partNumber) },
                            upload_id: uploadId
                        )
                    )
                )
            )
        )
        switch response {
        case .noContent:
            return
        case let .undocumented(statusCode: statusCode, _):
            throw MultipartUploadCompleteBuildsServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadCompleteBuildsServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw MultipartUploadCompleteBuildsServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw MultipartUploadCompleteBuildsServiceError.unauthorized(error.message)
            }
        }
    }
}
