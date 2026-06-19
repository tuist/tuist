import Foundation
import Mockable
import TuistHTTP

@Mockable
public protocol MultipartUploadGenerateURLShardsServicing {
    func generateUploadURL(
        fullHandle: String,
        serverURL: URL,
        shardPlanId: String?,
        reference: String,
        uploadId: String,
        partNumber: Int
    ) async throws -> String
}

public enum MultipartUploadGenerateURLShardsServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case badRequest(String)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to generate shard upload URL due to an unknown server response of \(statusCode)."
        case let .badRequest(message), let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public struct MultipartUploadGenerateURLShardsService: MultipartUploadGenerateURLShardsServicing {
    private let fullHandleService: FullHandleServicing

    public init(
        fullHandleService: FullHandleServicing = FullHandleService()
    ) {
        self.fullHandleService = fullHandleService
    }

    public func generateUploadURL(
        fullHandle: String,
        serverURL: URL,
        shardPlanId: String?,
        reference: String,
        uploadId: String,
        partNumber: Int
    ) async throws -> String {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.generateShardUploadURL(
            path: .init(
                account_handle: handles.accountHandle,
                project_handle: handles.projectHandle
            ),
            body: .json(
                .init(
                    part_number: partNumber,
                    reference: reference,
                    shard_plan_id: shardPlanId,
                    upload_id: uploadId
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(result):
                guard let url = result.data?.url else {
                    throw MultipartUploadGenerateURLShardsServiceError.unknownError(200)
                }
                return url
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadGenerateURLShardsServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw MultipartUploadGenerateURLShardsServiceError.unauthorized(error.message)
            }
        case let .badRequest(badRequestResponse):
            switch badRequestResponse.body {
            case let .json(error):
                throw MultipartUploadGenerateURLShardsServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode, _):
            throw MultipartUploadGenerateURLShardsServiceError.unknownError(statusCode)
        }
    }
}
