import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol MultipartUploadCompletePreviewsServicing {
    func completePreviewUpload(
        _ appBuildId: String,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)],
        fullHandle: String,
        serverURL: URL
    ) async throws -> ServerPreview
}

public enum MultipartUploadCompletePreviewsServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)
    case invalidPreview(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The multi-part upload could not get completed due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        case let .invalidPreview(id):
            return "The preview \(id) is invalid."
        }
    }
}

public final class MultipartUploadCompletePreviewsService: MultipartUploadCompletePreviewsServicing {
    private let fullHandleService: FullHandleServicing

    public convenience init() {
        self.init(
            fullHandleService: FullHandleService()
        )
    }

    init(
        fullHandleService: FullHandleServicing
    ) {
        self.fullHandleService = fullHandleService
    }

    public func completePreviewUpload(
        _ appBuildId: String,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)],
        fullHandle: String,
        serverURL: URL
    ) async throws -> ServerPreview {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.completePreviewsMultipartUpload(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                body: .json(
                    .init(
                        app_build_id: appBuildId,
                        multipart_upload_parts: .init(
                            parts: parts
                                .map { .init(etag: $0.etag, part_number: $0.partNumber) },
                            upload_id: uploadId
                        ),
                        preview_id: appBuildId
                    )
                )
            )
        )
        switch response {
        case let .ok(previewUploadCompletionResponse):
            switch previewUploadCompletionResponse.body {
            case let .json(previewUploadCompletionResponse):
                guard let preview = ServerPreview(previewUploadCompletionResponse)
                else {
                    throw MultipartUploadCompletePreviewsServiceError.invalidPreview(previewUploadCompletionResponse.id)
                }

                return preview
            }
        case let .undocumented(statusCode: statusCode, _):
            throw MultipartUploadCompletePreviewsServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadCompletePreviewsServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw MultipartUploadCompletePreviewsServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw MultipartUploadCompletePreviewsServiceError.unauthorized(error.message)
            }
        }
    }
}
