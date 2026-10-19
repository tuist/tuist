import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias RunnerProfileCreateResult = Operations.createRunnerProfile.Output.Created.Body.jsonPayload

public enum RunnerProfilePlatform: String, CaseIterable, Sendable {
    case linux
    case macos
}

@Mockable
public protocol CreateRunnerProfileServicing {
    /// Creates a profile that pins a platform, a machine shape and, on macOS, an Xcode version.
    func createRunnerProfile(
        accountHandle: String,
        serverURL: URL,
        name: String,
        platform: RunnerProfilePlatform,
        vcpus: Int,
        memoryGB: Int,
        xcodeVersion: String?,
        saveCacheFromDefaultBranch: Bool?,
        saveCacheFromBranches: [String]?
    ) async throws -> RunnerProfileCreateResult
}

enum CreateRunnerProfileServiceError: LocalizedError, Equatable {
    case badRequest(String)
    case forbidden(String)
    case notFound(String)
    case unprocessableContent(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .badRequest(message), let .forbidden(message), let .notFound(message), let .unprocessableContent(message):
            return message
        case let .unknownError(statusCode):
            return "We could not create the runner profile due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct CreateRunnerProfileService: CreateRunnerProfileServicing {
    public init() {}

    public func createRunnerProfile(
        accountHandle: String,
        serverURL: URL,
        name: String,
        platform: RunnerProfilePlatform,
        vcpus: Int,
        memoryGB: Int,
        xcodeVersion: String?,
        saveCacheFromDefaultBranch: Bool?,
        saveCacheFromBranches: [String]?
    ) async throws -> RunnerProfileCreateResult {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.createRunnerProfile(
            .init(
                path: .init(account_handle: accountHandle),
                body: .json(
                    .init(
                        cache_writer_branches: saveCacheFromBranches,
                        cache_writer_default_branch: saveCacheFromDefaultBranch,
                        memory_gb: memoryGB,
                        name: name,
                        platform: platform == .macos ? .macos : .linux,
                        vcpus: vcpus,
                        xcode_version: xcodeVersion
                    )
                )
            )
        )
        switch response {
        case let .created(value): return try value.body.json
        case let .badRequest(value): throw CreateRunnerProfileServiceError.badRequest(try value.body.json.message)
        case let .forbidden(value): throw CreateRunnerProfileServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw CreateRunnerProfileServiceError.notFound(try value.body.json.message)
        case let .unprocessableContent(value):
            throw CreateRunnerProfileServiceError.unprocessableContent(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw CreateRunnerProfileServiceError.unknownError(statusCode)
        }
    }
}
