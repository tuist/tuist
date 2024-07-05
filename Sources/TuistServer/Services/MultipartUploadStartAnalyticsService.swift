import Foundation
import Mockable
import TuistSupport

@Mockable
public protocol MultipartUploadStartAnalyticsServicing {
    func uploadAnalyticsArtifact(
        _ artifact: ServerCommandEvent.Artifact,
        commandEventId: Int,
        serverURL: URL
    ) async throws -> String
}

public enum MultipartUploadStartAnalyticsServiceError: FatalError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case paymentRequired(String)
    case forbidden(String)
    case unauthorized(String)

    public var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .notFound, .paymentRequired, .forbidden, .unauthorized:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The remote cache artifact could not be uploaded due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .paymentRequired(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class MultipartUploadStartAnalyticsService: MultipartUploadStartAnalyticsServicing {
    public init() {}

    public func uploadAnalyticsArtifact(
        _ artifact: ServerCommandEvent.Artifact,
        commandEventId: Int,
        serverURL: URL
    ) async throws -> String {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.startAnalyticsArtifactMultipartUpload(
            .init(
                path: .init(run_id: commandEventId),
                body: .json(.init(artifact))
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(cacheArtifact):
                return cacheArtifact.data.upload_id
            }
        case let .undocumented(statusCode: statusCode, _):
            throw MultipartUploadStartAnalyticsServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadStartAnalyticsServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw MultipartUploadStartAnalyticsServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        }
    }
}
