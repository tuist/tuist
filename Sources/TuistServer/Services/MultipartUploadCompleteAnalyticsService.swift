import Foundation
import Mockable
import OpenAPIRuntime
import TuistSupport

@Mockable
public protocol MultipartUploadCompleteAnalyticsServicing {
    func uploadAnalyticsArtifact(
        _ artifact: ServerCommandEvent.Artifact,
        commandEventId: Int,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)],
        serverURL: URL
    ) async throws
}

public enum MultipartUploadCompleteAnalyticsServiceError: FatalError, Equatable {
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
            return "The multi-part upload could not get completed due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class MultipartUploadCompleteAnalyticsService: MultipartUploadCompleteAnalyticsServicing {
    public init() {}

    public func uploadAnalyticsArtifact(
        _ artifact: ServerCommandEvent.Artifact,
        commandEventId: Int,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)],
        serverURL: URL
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.completeAnalyticsArtifactMultipartUpload(
            .init(
                path: .init(run_id: commandEventId),
                body: .json(
                    .init(
                        command_event_artifact: .init(artifact),
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
            throw MultipartUploadCompleteAnalyticsServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadCompleteAnalyticsServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw MultipartUploadCompleteAnalyticsServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        }
    }
}
