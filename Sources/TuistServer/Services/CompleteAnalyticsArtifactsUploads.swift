import Foundation
import Mockable
import OpenAPIRuntime
import TuistSupport

@Mockable
public protocol CompleteAnalyticsArtifactsUploadsServicing {
    func completeAnalyticsArtifactsUploads(
        modules: [CloudModule],
        commandEventId: Int,
        serverURL: URL
    ) async throws
}

public enum CompleteAnalyticsArtifactsUploadsServiceError: FatalError, Equatable {
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
            return "The analytics artifacts uploads could not get completed due to an unknown Tuist Cloud response of \(statusCode)."
        case let .notFound(message), let .forbidden(message):
            return message
        }
    }
}

public final class CompleteAnalyticsArtifactsUploadsService: CompleteAnalyticsArtifactsUploadsServicing {
    public init() {}

    public func completeAnalyticsArtifactsUploads(
        modules: [CloudModule],
        commandEventId: Int,
        serverURL: URL
    ) async throws {
        let client = Client.cloud(serverURL: serverURL)
        let response = try await client.completeAnalyticsArtifactsUploads(
            .init(
                path: .init(run_id: commandEventId),
                body: .json(
                    .init(modules: .init(modules.map(Components.Schemas.Module.init)))
                )
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
        }
    }
}
