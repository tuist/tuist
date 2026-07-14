import Foundation
import Mockable
import TuistHTTP

@Mockable
public protocol MultipartUploadCompleteShardsServicing {
    func completeUpload(
        fullHandle: String,
        serverURL: URL,
        shardPlanId: String?,
        reference: String,
        uploadId: String,
        parts: [(partNumber: Int, etag: String)],
        artifact: String?
    ) async throws
}

public enum MultipartUploadCompleteShardsServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case badRequest(String)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to complete shard upload due to an unknown server response of \(statusCode)."
        case let .badRequest(message), let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public struct MultipartUploadCompleteShardsService: MultipartUploadCompleteShardsServicing {
    private let fullHandleService: FullHandleServicing

    public init(
        fullHandleService: FullHandleServicing = FullHandleService()
    ) {
        self.fullHandleService = fullHandleService
    }

    public func completeUpload(
        fullHandle: String,
        serverURL: URL,
        shardPlanId: String?,
        reference: String,
        uploadId: String,
        parts: [(partNumber: Int, etag: String)],
        artifact: String? = nil
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let partsPayload = parts.map { part in
            Operations.completeShardUpload.Input.Body.jsonPayload.partsPayloadPayload(
                etag: part.etag,
                part_number: part.partNumber
            )
        }

        let response = try await client.completeShardUpload(
            path: .init(
                account_handle: handles.accountHandle,
                project_handle: handles.projectHandle
            ),
            body: .json(
                .init(
                    artifact: artifact,
                    parts: partsPayload,
                    reference: reference,
                    shard_plan_id: shardPlanId,
                    upload_id: uploadId
                )
            )
        )

        switch response {
        case .ok:
            return
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadCompleteShardsServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw MultipartUploadCompleteShardsServiceError.unauthorized(error.message)
            }
        case let .badRequest(badRequestResponse):
            switch badRequestResponse.body {
            case let .json(error):
                throw MultipartUploadCompleteShardsServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode, _):
            throw MultipartUploadCompleteShardsServiceError.unknownError(statusCode)
        }
    }
}
