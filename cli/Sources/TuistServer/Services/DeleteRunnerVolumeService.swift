import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias RunnerVolumeDeleteResult = Operations.deleteRunnerVolume.Output.Ok.Body.jsonPayload

@Mockable
public protocol DeleteRunnerVolumeServicing {
    func deleteRunnerVolume(accountHandle: String, serverURL: URL, volumeID: String) async throws -> RunnerVolumeDeleteResult
}

enum DeleteRunnerVolumeServiceError: LocalizedError, Equatable {
    case badRequest(String)
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .badRequest(message), let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not delete the runner volume due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct DeleteRunnerVolumeService: DeleteRunnerVolumeServicing {
    public init() {}

    public func deleteRunnerVolume(
        accountHandle: String,
        serverURL: URL,
        volumeID: String
    ) async throws -> RunnerVolumeDeleteResult {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.deleteRunnerVolume(.init(path: .init(account_handle: accountHandle, volume_id: volumeID)))
        switch response {
        case let .ok(value): return try value.body.json
        case let .badRequest(value): throw DeleteRunnerVolumeServiceError.badRequest(try value.body.json.message)
        case let .forbidden(value): throw DeleteRunnerVolumeServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw DeleteRunnerVolumeServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw DeleteRunnerVolumeServiceError.unknownError(statusCode)
        }
    }
}
