import Foundation
import Mockable
import OpenAPIRuntime
import TuistSupport

@Mockable
public protocol MultipartUploadCompletePreviewsServicing {
    func completePreviewUpload(
        _ previewId: String,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)],
        fullHandle: String,
        serverURL: URL
    ) async throws -> URL
}

public enum MultipartUploadCompletePreviewsServiceError: FatalError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)
    case invalidURL(String)

    public var type: ErrorType {
        switch self {
        case .unknownError, .invalidURL:
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
        case let .invalidURL(url):
            return "The app build download URL \(url) returned from the server is invalid."
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
        _ previewId: String,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)],
        fullHandle: String,
        serverURL: URL
    ) async throws -> URL {
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
                        multipart_upload_parts: .init(
                            parts: parts
                                .map { .init(etag: $0.etag, part_number: $0.partNumber) },
                            upload_id: uploadId
                        ),
                        preview_id: previewId
                    )
                )
            )
        )
        switch response {
        case let .ok(previewUploadCompletionResponse):
            switch previewUploadCompletionResponse.body {
            case let .json(previewUploadCompletionResponse):
                guard let url = URL(string: previewUploadCompletionResponse.url)
                else {
                    throw MultipartUploadCompletePreviewsServiceError.invalidURL(previewUploadCompletionResponse.url)
                }

                return url
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
