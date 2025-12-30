import Foundation
import Mockable
import OpenAPIRuntime

@Mockable
public protocol MultipartUploadCompleteAnalyticsServicing {
    func uploadAnalyticsArtifact(
        _ artifact: ServerCommandEvent.Artifact,
        accountHandle: String,
        projectHandle: String,
        commandEventId: String,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)],
        serverURL: URL
    ) async throws
}

public enum MultipartUploadCompleteAnalyticsServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)
    case internalServerError(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The multi-part upload could not get completed due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message), let .internalServerError(message):
            return message
        }
    }
}

public final class MultipartUploadCompleteAnalyticsService: MultipartUploadCompleteAnalyticsServicing {
    public init() {}

    public func uploadAnalyticsArtifact(
        _ artifact: ServerCommandEvent.Artifact,
        accountHandle: String,
        projectHandle: String,
        commandEventId: String,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)],
        serverURL: URL
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.completeAnalyticsArtifactMultipartUploadProject(
            path: .init(account_handle: accountHandle, project_handle: projectHandle, run_id: commandEventId),
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
                throw MultipartUploadCompleteAnalyticsServiceError.unauthorized(error.message)
            }
        case let .internalServerError(internalServerError):
            switch internalServerError.body {
            case let .json(error):
                throw MultipartUploadCompleteAnalyticsServiceError.internalServerError(error.message)
            }
        }
    }
}
