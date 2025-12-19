import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol UploadModuleCachePartServicing: Sendable {
    func uploadPart(
        accountHandle: String,
        projectHandle: String,
        uploadId: String,
        partNumber: Int,
        data: Data,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws
}

public enum UploadModuleCachePartServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case badRequest(String)
    case notFound(String)
    case partTooLarge(String)
    case totalSizeExceeded(String)
    case requestTimeout(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to upload part due to an unknown response of \(statusCode)."
        case let .unauthorized(message),
             let .forbidden(message),
             let .badRequest(message),
             let .notFound(message),
             let .partTooLarge(message),
             let .totalSizeExceeded(message),
             let .requestTimeout(message):
            return message
        }
    }
}

public struct UploadModuleCachePartService: UploadModuleCachePartServicing {
    public init() {}

    public func uploadPart(
        accountHandle: String,
        projectHandle: String,
        uploadId: String,
        partNumber: Int,
        data: Data,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        )

        let response = try await client.uploadModuleCachePart(
            .init(
                query: .init(
                    account_handle: accountHandle,
                    project_handle: projectHandle,
                    upload_id: uploadId,
                    part_number: partNumber
                ),
                body: .binary(HTTPBody(data))
            )
        )

        switch response {
        case .noContent:
            return
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw UploadModuleCachePartServiceError.notFound(error.message)
            }
        case let .contentTooLarge(tooLarge):
            switch tooLarge.body {
            case let .json(error):
                throw UploadModuleCachePartServiceError.partTooLarge(error.message)
            }
        case let .unprocessableContent(unprocessable):
            switch unprocessable.body {
            case let .json(error):
                throw UploadModuleCachePartServiceError.totalSizeExceeded(error.message)
            }
        case let .requestTimeout(timeout):
            switch timeout.body {
            case let .json(error):
                throw UploadModuleCachePartServiceError.requestTimeout(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw UploadModuleCachePartServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw UploadModuleCachePartServiceError.forbidden(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw UploadModuleCachePartServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UploadModuleCachePartServiceError.unknownError(statusCode)
        }
    }
}
