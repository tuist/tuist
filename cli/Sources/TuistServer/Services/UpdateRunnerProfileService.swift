import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias RunnerProfileUpdateResult = Operations.updateRunnerProfile.Output.Ok.Body.jsonPayload

/// Changes to a runner profile. `nil` fields keep their value.
public struct RunnerProfileChanges: Equatable, Sendable {
    public var vcpus: Int?
    public var memoryGB: Int?
    public var xcodeVersion: String?
    public var saveCacheFromDefaultBranch: Bool?
    public var saveCacheFromBranches: [String]?

    public init(
        vcpus: Int? = nil,
        memoryGB: Int? = nil,
        xcodeVersion: String? = nil,
        saveCacheFromDefaultBranch: Bool? = nil,
        saveCacheFromBranches: [String]? = nil
    ) {
        self.vcpus = vcpus
        self.memoryGB = memoryGB
        self.xcodeVersion = xcodeVersion
        self.saveCacheFromDefaultBranch = saveCacheFromDefaultBranch
        self.saveCacheFromBranches = saveCacheFromBranches
    }
}

@Mockable
public protocol UpdateRunnerProfileServicing {
    /// Changes the profile's machine shape, Xcode version, or which branches save its cache volumes.
    func updateRunnerProfile(
        accountHandle: String,
        serverURL: URL,
        profileName: String,
        changes: RunnerProfileChanges
    ) async throws -> RunnerProfileUpdateResult
}

enum UpdateRunnerProfileServiceError: LocalizedError, Equatable {
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
            return "We could not update the runner profile due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct UpdateRunnerProfileService: UpdateRunnerProfileServicing {
    public init() {}

    public func updateRunnerProfile(
        accountHandle: String,
        serverURL: URL,
        profileName: String,
        changes: RunnerProfileChanges
    ) async throws -> RunnerProfileUpdateResult {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.updateRunnerProfile(
            .init(
                path: .init(account_handle: accountHandle, profile_name: profileName),
                body: .json(
                    .init(
                        cache_writer_branches: changes.saveCacheFromBranches,
                        cache_writer_default_branch: changes.saveCacheFromDefaultBranch,
                        memory_gb: changes.memoryGB,
                        vcpus: changes.vcpus,
                        xcode_version: changes.xcodeVersion
                    )
                )
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .badRequest(value): throw UpdateRunnerProfileServiceError.badRequest(try value.body.json.message)
        case let .forbidden(value): throw UpdateRunnerProfileServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw UpdateRunnerProfileServiceError.notFound(try value.body.json.message)
        case let .unprocessableContent(value):
            throw UpdateRunnerProfileServiceError.unprocessableContent(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw UpdateRunnerProfileServiceError.unknownError(statusCode)
        }
    }
}
