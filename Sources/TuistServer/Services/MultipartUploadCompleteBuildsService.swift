import Foundation
import Mockable
import OpenAPIRuntime
import TuistSupport

@Mockable
public protocol MultipartUploadCompleteAppBuildsServicing {
    func completeAppBuildUpload(
        _ appBuildId: String,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)],
        fullHandle: String,
        serverURL: URL
    ) async throws -> URL
}

public enum MultipartUploadCompleteAppBuildsServiceError: FatalError, Equatable {
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

public final class MultipartUploadCompleteBuildsService: MultipartUploadCompleteAppBuildsServicing {
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

    public func completeAppBuildUpload(
        _ appBuildId: String,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)],
        fullHandle: String,
        serverURL: URL
    ) async throws -> URL {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.completeAppBuildsMultipartUpload(
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
                        )
                    )
                )
            )
        )
        switch response {
        case let .ok(appBuildUploadCompletionResponse):
            switch appBuildUploadCompletionResponse.body {
            case let .json(appBuildUploadCompletionResponse):
                guard let url = URL(string: appBuildUploadCompletionResponse.url)
                else {
                    throw MultipartUploadCompleteAppBuildsServiceError.invalidURL(appBuildUploadCompletionResponse.url)
                }

                return url
            }
        case let .undocumented(statusCode: statusCode, _):
            throw MultipartUploadCompleteAppBuildsServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadCompleteAppBuildsServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw MultipartUploadCompleteAppBuildsServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw MultipartUploadCompleteAppBuildsServiceError.unauthorized(error.message)
            }
        }
    }
}
