import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

/// A run's place in the repository's history, as the client sends it with the run. The server
/// keeps whatever is set and may complete the rest from the VCS provider.
public struct TestRunGitHistory: Equatable, Sendable {
    public struct ChangedFile: Equatable, Sendable {
        public let path: String
        public let previousPath: String?
        /// `added`, `modified`, `deleted` or `renamed`.
        public let status: String
        public let blobId: String?
        /// Inclusive line ranges changed at the head, as `(start, end)`.
        public let hunks: [(start: Int, end: Int)]
        public let truncated: Bool

        public init(
            path: String,
            previousPath: String?,
            status: String,
            blobId: String?,
            hunks: [(start: Int, end: Int)],
            truncated: Bool
        ) {
            self.path = path
            self.previousPath = previousPath
            self.status = status
            self.blobId = blobId
            self.hunks = hunks
            self.truncated = truncated
        }

        public static func == (lhs: ChangedFile, rhs: ChangedFile) -> Bool {
            lhs.path == rhs.path && lhs.previousPath == rhs.previousPath && lhs.status == rhs.status
                && lhs.blobId == rhs.blobId && lhs.truncated == rhs.truncated
                && lhs.hunks.map(\.start) == rhs.hunks.map(\.start) && lhs.hunks.map(\.end) == rhs.hunks.map(\.end)
        }
    }

    public let baseBranch: String?
    public let mergeBaseSHA: String?
    public let isPullRequest: Bool
    public let pullRequestNumber: Int?
    /// `sha1` or `sha256`.
    public let objectFormat: String?
    /// Whether the client collected the history (`client`) or could not (`none`).
    public let source: String
    public let fallbackReason: String?
    public let changedFiles: [ChangedFile]

    public init(
        baseBranch: String?,
        mergeBaseSHA: String?,
        isPullRequest: Bool,
        pullRequestNumber: Int?,
        objectFormat: String?,
        source: String,
        fallbackReason: String?,
        changedFiles: [ChangedFile]
    ) {
        self.baseBranch = baseBranch
        self.mergeBaseSHA = mergeBaseSHA
        self.isPullRequest = isPullRequest
        self.pullRequestNumber = pullRequestNumber
        self.objectFormat = objectFormat
        self.source = source
        self.fallbackReason = fallbackReason
        self.changedFiles = changedFiles
    }
}

/// How much history the server wants a client to collect and upload.
public struct GitHistorySettings: Equatable, Sendable {
    public let windowDays: Int
    public let windowCommits: Int
    public let deepenBudgetSeconds: Int
    public let uploadBatchSize: Int

    public init(windowDays: Int, windowCommits: Int, deepenBudgetSeconds: Int, uploadBatchSize: Int) {
        self.windowDays = windowDays
        self.windowCommits = windowCommits
        self.deepenBudgetSeconds = deepenBudgetSeconds
        self.uploadBatchSize = uploadBatchSize
    }
}

/// A commit for the server's commit graph.
public struct GitHistoryCommitPayload: Equatable, Sendable {
    public let sha: String
    public let parents: [String]
    public let committedAt: Date

    public init(sha: String, parents: [String], committedAt: Date) {
        self.sha = sha
        self.parents = parents
        self.committedAt = committedAt
    }
}

enum GitHistoryServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The Git history request failed with an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

@Mockable
public protocol GetGitHistorySettingsServicing {
    func getGitHistorySettings(fullHandle: String, serverURL: URL) async throws -> GitHistorySettings
}

public struct GetGitHistorySettingsService: GetGitHistorySettingsServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func getGitHistorySettings(fullHandle: String, serverURL: URL) async throws -> GitHistorySettings {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.getGitHistorySettings(
            .init(path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle))
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(settings):
                return GitHistorySettings(
                    windowDays: settings.window_days,
                    windowCommits: settings.window_commits,
                    deepenBudgetSeconds: settings.deepen_budget_seconds,
                    uploadBatchSize: settings.upload_batch_size
                )
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error): throw GitHistoryServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error): throw GitHistoryServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error): throw GitHistoryServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GitHistoryServiceError.unknownError(statusCode)
        }
    }
}

@Mockable
public protocol FindMissingCommitsServicing {
    func findMissingCommits(fullHandle: String, serverURL: URL, shas: [String]) async throws -> [String]
}

public struct FindMissingCommitsService: FindMissingCommitsServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func findMissingCommits(fullHandle: String, serverURL: URL, shas: [String]) async throws -> [String] {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.findMissingCommits(
            .init(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                body: .json(.init(shas: shas))
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(payload): return payload.missing
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error): throw GitHistoryServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error): throw GitHistoryServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error): throw GitHistoryServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GitHistoryServiceError.unknownError(statusCode)
        }
    }
}

@Mockable
public protocol UploadCommitsServicing {
    func uploadCommits(
        fullHandle: String,
        serverURL: URL,
        objectFormat: String,
        commits: [GitHistoryCommitPayload],
        branchHeads: [(branch: String, sha: String)]
    ) async throws
}

public struct UploadCommitsService: UploadCommitsServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func uploadCommits(
        fullHandle: String,
        serverURL: URL,
        objectFormat: String,
        commits: [GitHistoryCommitPayload],
        branchHeads: [(branch: String, sha: String)]
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.uploadCommits(
            .init(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                body: .json(
                    .init(
                        branch_heads: branchHeads.map { .init(branch: $0.branch, sha: $0.sha) },
                        commits: commits.map { .init(committed_at: $0.committedAt, parents: $0.parents, sha: $0.sha) },
                        object_format: objectFormat == "sha256" ? .sha256 : .sha1
                    )
                )
            )
        )
        switch response {
        case .noContent:
            return
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error): throw GitHistoryServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error): throw GitHistoryServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error): throw GitHistoryServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GitHistoryServiceError.unknownError(statusCode)
        }
    }
}
