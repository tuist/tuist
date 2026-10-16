import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias RunnerVolumeClearResult = Operations.clearRunnerVolume.Output.Ok.Body.jsonPayload

@Mockable
public protocol ClearRunnerVolumeServicing {
    func clearRunnerVolume(accountHandle: String, serverURL: URL, volumeID: String) async throws -> RunnerVolumeClearResult
}

enum ClearRunnerVolumeServiceError: LocalizedError, Equatable {
    case badRequest(String)
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .badRequest(message), let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not clear the runner volume due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct ClearRunnerVolumeService: ClearRunnerVolumeServicing {
    public init() {}

    public func clearRunnerVolume(
        accountHandle: String,
        serverURL: URL,
        volumeID: String
    ) async throws -> RunnerVolumeClearResult {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.clearRunnerVolume(.init(path: .init(account_handle: accountHandle, volume_id: volumeID)))
        switch response {
        case let .ok(value): return try value.body.json
        case let .badRequest(value): throw ClearRunnerVolumeServiceError.badRequest(try value.body.json.message)
        case let .forbidden(value): throw ClearRunnerVolumeServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw ClearRunnerVolumeServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw ClearRunnerVolumeServiceError.unknownError(statusCode)
        }
    }
}
