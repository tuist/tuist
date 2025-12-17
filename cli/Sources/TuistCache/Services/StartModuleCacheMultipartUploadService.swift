import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol StartModuleCacheMultipartUploadServicing: Sendable {
    func startUpload(
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> String?
}

public enum StartModuleCacheMultipartUploadServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case badRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to start multipart upload due to an unknown response of \(statusCode)."
        case let .unauthorized(message),
             let .forbidden(message),
             let .badRequest(message):
            return message
        }
    }
}

public struct StartModuleCacheMultipartUploadService: StartModuleCacheMultipartUploadServicing {
    public init() {}

    public func startUpload(
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> String? {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        )

        let response = try await client.startModuleCacheMultipartUpload(
            .init(
                query: .init(
                    account_handle: accountHandle,
                    project_handle: projectHandle,
                    hash: hash,
                    name: name,
                    cache_category: cacheCategory
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(body):
                return body.upload_id
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw StartModuleCacheMultipartUploadServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw StartModuleCacheMultipartUploadServiceError.forbidden(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw StartModuleCacheMultipartUploadServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw StartModuleCacheMultipartUploadServiceError.unknownError(statusCode)
        }
    }
}
