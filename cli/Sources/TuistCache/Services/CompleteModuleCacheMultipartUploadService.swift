import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol CompleteModuleCacheMultipartUploadServicing: Sendable {
    func completeUpload(
        accountHandle: String,
        projectHandle: String,
        uploadId: String,
        parts: [Int],
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws
}

public enum CompleteModuleCacheMultipartUploadServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case badRequest(String)
    case notFound(String)
    case internalServerError(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to complete multipart upload due to an unknown response of \(statusCode)."
        case let .unauthorized(message),
             let .forbidden(message),
             let .badRequest(message),
             let .notFound(message),
             let .internalServerError(message):
            return message
        }
    }
}

public struct CompleteModuleCacheMultipartUploadService: CompleteModuleCacheMultipartUploadServicing {
    public init() {}

    public func completeUpload(
        accountHandle: String,
        projectHandle: String,
        uploadId: String,
        parts: [Int],
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        )

        let response = try await client.completeModuleCacheMultipartUpload(
            .init(
                query: .init(
                    account_handle: accountHandle,
                    project_handle: projectHandle,
                    upload_id: uploadId
                ),
                body: .json(.init(parts: parts))
            )
        )

        switch response {
        case .noContent:
            return
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw CompleteModuleCacheMultipartUploadServiceError.notFound(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw CompleteModuleCacheMultipartUploadServiceError.badRequest(error.message)
            }
        case let .internalServerError(serverError):
            switch serverError.body {
            case let .json(error):
                throw CompleteModuleCacheMultipartUploadServiceError.internalServerError(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw CompleteModuleCacheMultipartUploadServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw CompleteModuleCacheMultipartUploadServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CompleteModuleCacheMultipartUploadServiceError.unknownError(statusCode)
        }
    }
}
