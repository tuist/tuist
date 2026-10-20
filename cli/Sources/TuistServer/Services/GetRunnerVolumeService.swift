import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias RunnerVolume = Operations.getRunnerVolume.Output.Ok.Body.jsonPayload

@Mockable
public protocol GetRunnerVolumeServicing {
    func getRunnerVolume(accountHandle: String, serverURL: URL, volumeID: String) async throws -> RunnerVolume
}

enum GetRunnerVolumeServiceError: LocalizedError, Equatable {
    case badRequest(String)
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .badRequest(message), let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not get the runner volume due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct GetRunnerVolumeService: GetRunnerVolumeServicing {
    public init() {}

    public func getRunnerVolume(accountHandle: String, serverURL: URL, volumeID: String) async throws -> RunnerVolume {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.getRunnerVolume(.init(path: .init(account_handle: accountHandle, volume_id: volumeID)))
        switch response {
        case let .ok(value): return try value.body.json
        case let .badRequest(value): throw GetRunnerVolumeServiceError.badRequest(try value.body.json.message)
        case let .forbidden(value): throw GetRunnerVolumeServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw GetRunnerVolumeServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw GetRunnerVolumeServiceError.unknownError(statusCode)
        }
    }
}
