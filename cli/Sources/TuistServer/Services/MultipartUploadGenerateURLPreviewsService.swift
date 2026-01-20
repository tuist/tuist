import Foundation
import Mockable
import TuistHTTP

@Mockable
public protocol MultipartUploadGenerateURLPreviewsServicing {
    func uploadPreview(
        _ appBuildId: String,
        partNumber: Int,
        uploadId: String,
        fullHandle: String,
        serverURL: URL,
        contentLength: Int
    ) async throws -> String
}

public enum MultipartUploadGenerateURLPreviewsServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The generation of a multi-part upload URL failed due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class MultipartUploadGenerateURLPreviewsService: MultipartUploadGenerateURLPreviewsServicing {
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

    public func uploadPreview(
        _ appBuildId: String,
        partNumber: Int,
        uploadId: String,
        fullHandle: String,
        serverURL: URL,
        contentLength: Int
    ) async throws -> String {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.generatePreviewsMultipartUploadURL(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                body: .json(
                    .init(
                        app_build_id: appBuildId,
                        multipart_upload_part: .init(
                            content_length: contentLength,
                            part_number: partNumber,
                            upload_id: uploadId
                        ),
                        preview_id: appBuildId
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
            throw MultipartUploadGenerateURLPreviewsServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadGenerateURLPreviewsServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw MultipartUploadGenerateURLPreviewsServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw MultipartUploadGenerateURLPreviewsServiceError.unauthorized(error.message)
            }
        }
    }
}
