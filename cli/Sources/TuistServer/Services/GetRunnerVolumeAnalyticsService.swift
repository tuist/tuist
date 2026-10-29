import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias RunnerVolumeAnalytics = Operations.getRunnerVolumeAnalytics.Output.Ok.Body.jsonPayload

@Mockable
public protocol GetRunnerVolumeAnalyticsServicing {
    func getRunnerVolumeAnalytics(
        accountHandle: String,
        serverURL: URL,
        volumeID: String?,
        start: Date?,
        end: Date?
    ) async throws -> RunnerVolumeAnalytics
}

enum GetRunnerVolumeAnalyticsServiceError: LocalizedError, Equatable {
    case badRequest(String)
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .badRequest(message), let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not get runner volume analytics due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct GetRunnerVolumeAnalyticsService: GetRunnerVolumeAnalyticsServicing {
    public init() {}

    public func getRunnerVolumeAnalytics(
        accountHandle: String,
        serverURL: URL,
        volumeID: String?,
        start: Date?,
        end: Date?
    ) async throws -> RunnerVolumeAnalytics {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.getRunnerVolumeAnalytics(.init(
            path: .init(account_handle: accountHandle),
            query: .init(end: end, start: start, volume_id: volumeID)
        ))
        switch response {
        case let .ok(value): return try value.body.json
        case let .badRequest(value): throw GetRunnerVolumeAnalyticsServiceError.badRequest(try value.body.json.message)
        case let .forbidden(value): throw GetRunnerVolumeAnalyticsServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw GetRunnerVolumeAnalyticsServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw GetRunnerVolumeAnalyticsServiceError.unknownError(statusCode)
        }
    }
}
