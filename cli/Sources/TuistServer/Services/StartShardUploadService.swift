import Foundation
import Mockable
import TuistHTTP

@Mockable
public protocol StartShardUploadServicing {
    func startUpload(
        fullHandle: String,
        serverURL: URL,
        shardPlanId: String?,
        reference: String,
        artifact: String?
    ) async throws -> String
}

public enum StartShardUploadServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case badRequest(String)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to start shard upload due to an unknown server response of \(statusCode)."
        case let .badRequest(message), let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public struct StartShardUploadService: StartShardUploadServicing {
    private let fullHandleService: FullHandleServicing

    public init(
        fullHandleService: FullHandleServicing = FullHandleService()
    ) {
        self.fullHandleService = fullHandleService
    }

    public func startUpload(
        fullHandle: String,
        serverURL: URL,
        shardPlanId: String? = nil,
        reference: String,
        artifact: String? = nil
    ) async throws -> String {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.startShardUpload(
            path: .init(
                account_handle: handles.accountHandle,
                project_handle: handles.projectHandle
            ),
            body: .json(
                .init(
                    artifact: artifact,
                    reference: reference,
                    shard_plan_id: shardPlanId
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(result):
                guard let uploadId = result.data?.upload_id else {
                    throw StartShardUploadServiceError.unknownError(200)
                }
                return uploadId
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw StartShardUploadServiceError.forbidden(error.message)
            }
        case let .badRequest(badRequestResponse):
            switch badRequestResponse.body {
            case let .json(error):
                throw StartShardUploadServiceError.badRequest(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw StartShardUploadServiceError.unauthorized(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw StartShardUploadServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode, _):
            throw StartShardUploadServiceError.unknownError(statusCode)
        }
    }
}
