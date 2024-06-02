import Foundation
import Mockable
import TuistSupport

@Mockable
public protocol MultipartUploadGenerateURLAnalyticsServicing {
    func uploadAnalytics(
        commandEventId: Int,
        partNumber: Int,
        uploadId: String,
        serverURL: URL
    ) async throws -> String
}

public enum MultipartUploadGenerateURLAnalyticsServiceError: FatalError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)

    public var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .notFound, .forbidden:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The generation of a multi-part upload URL failed due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .forbidden(message):
            return message
        }
    }
}

public final class MultipartUploadGenerateURLAnalyticsService: MultipartUploadGenerateURLAnalyticsServicing {
    public init() {}

    public func uploadAnalytics(
        commandEventId: Int,
        partNumber: Int,
        uploadId: String,
        serverURL: URL
    ) async throws -> String {
        let client = Client.cloud(serverURL: serverURL)
        let response = try await client.generateAnalyticsArtifactMultipartUploadURL(
            .init(
                path: .init(run_id: commandEventId),
                body: .json(
                    .init(
                        command_event_artifact: .init(
                            _type: .result_bundle
                        ),
                        multipart_upload_part: .init(
                            part_number: partNumber,
                            upload_id: uploadId
                        )
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
            throw MultipartUploadGenerateURLAnalyticsServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadGenerateURLAnalyticsServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw MultipartUploadGenerateURLAnalyticsServiceError.notFound(error.message)
            }
        }
    }
}
