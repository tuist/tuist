import Foundation
import Mockable
import OpenAPIRuntime

@Mockable
public protocol CompleteAnalyticsArtifactsUploadsServicing {
    func completeAnalyticsArtifactsUploads(
        accountHandle: String,
        projectHandle: String,
        commandEventId: String,
        serverURL: URL
    ) async throws
}

public enum CompleteAnalyticsArtifactsUploadsServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The analytics artifacts uploads could not get completed due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class CompleteAnalyticsArtifactsUploadsService: CompleteAnalyticsArtifactsUploadsServicing {
    public init() {}

    public func completeAnalyticsArtifactsUploads(
        accountHandle: String,
        projectHandle: String,
        commandEventId: String,
        serverURL: URL
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.completeAnalyticsArtifactsUploadsProject(
            .init(
                path: .init(account_handle: accountHandle, project_handle: projectHandle, run_id: commandEventId)
            )
        )
        switch response {
        case .noContent:
            return
        case let .undocumented(statusCode: statusCode, _):
            throw CompleteAnalyticsArtifactsUploadsServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw CompleteAnalyticsArtifactsUploadsServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw CompleteAnalyticsArtifactsUploadsServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw CompleteAnalyticsArtifactsUploadsServiceError.unauthorized(error.message)
            }
        }
    }
}
