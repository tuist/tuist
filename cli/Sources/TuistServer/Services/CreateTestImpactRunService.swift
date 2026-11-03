import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol CreateTestImpactRunServicing {
    /// Creates the invocation's impact run: the tests coverage selected, or a recorded fallback.
    /// Never throws: a failed or timed-out request comes back as `.failed`, and the run falls back
    /// without a record.
    func createTestImpactRun(
        fullHandle: String,
        serverURL: URL,
        request: TestImpactRunRequest
    ) async -> TestImpactRunOutcome
}

public struct CreateTestImpactRunService: CreateTestImpactRunServicing {
    /// The most changed files the server analyzes. Past it, the first ones in path order are sent
    /// with the total, and the server falls back with `diff_too_large`.
    static let changedFilesLimit = 5000

    private let fullHandleService: FullHandleServicing
    private let timeout: Duration

    public init(
        fullHandleService: FullHandleServicing = FullHandleService(),
        timeout: Duration = .seconds(2)
    ) {
        self.fullHandleService = fullHandleService
        self.timeout = timeout
    }

    public func createTestImpactRun(
        fullHandle: String,
        serverURL: URL,
        request: TestImpactRunRequest
    ) async -> TestImpactRunOutcome {
        do {
            let handles = try fullHandleService.parse(fullHandle)
            let client = Client.authenticated(serverURL: serverURL)
            let input = Operations.createTestImpactRun.Input(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                body: .json(Self.body(for: request))
            )
            guard let response = try await withTestImpactTimeout(timeout, { try await client.createTestImpactRun(input) })
            else {
                return .failed("The test impact run request didn't finish within \(timeout.components.seconds)s.")
            }
            return Self.outcome(from: response)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func body(for request: TestImpactRunRequest) -> Operations.createTestImpactRun.Input.Body.jsonPayload {
        var baselineSHA: String?
        var fallbackReason: String?
        var changedFiles: [Operations.createTestImpactRun.Input.Body.jsonPayload.changed_filesPayloadPayload]?
        var changedFilesCount: Int?
        var dirty: Bool?
        switch request.basis {
        case let .baseline(sha, files, isDirty):
            baselineSHA = sha
            dirty = isDirty ? true : nil
            if let files {
                changedFiles = files.sorted { $0.path < $1.path }.prefix(changedFilesLimit).map {
                    .init(affected_modules: $0.affectedModules, blob: $0.blob, path: $0.path, status: $0.status)
                }
                changedFilesCount = files.count
            }
        case let .fallback(reason):
            fallbackReason = reason.rawValue
        }
        let hasScope = request.scheme != nil || request.testPlan != nil || request.destination != nil
        return .init(
            baseline_sha: baselineSHA,
            build_system: request.buildSystem,
            changed_files: changedFiles,
            changed_files_count: changedFilesCount,
            commit_sha: request.commitSHA,
            dirty: dirty,
            fallback_reason: fallbackReason,
            git_branch: request.gitBranch,
            head_sha: request.headSHA,
            modules: request.modules,
            platform: request.platform,
            xcode: hasScope ? .init(destination: request.destination, scheme: request.scheme, test_plan: request.testPlan) : nil
        )
    }

    static func outcome(from response: Operations.createTestImpactRun.Output) -> TestImpactRunOutcome {
        switch response {
        case let .ok(ok):
            switch ok.body {
            case let .json(run):
                // An outcome this client doesn't know means fallback.
                guard run.outcome == "selected" else {
                    return .fallback(
                        runID: run.id,
                        reason: run.reason.map(TestImpactFallbackReason.init(rawValue:)),
                        matchedPath: run.matched_path
                    )
                }
                return .selected(TestImpactSelection(
                    runID: run.id,
                    requested: run.counts?.requested,
                    selected: run.counts?.selected,
                    skipped: run.counts?.skipped,
                    skip: (run.skip ?? []).map { TestImpactSkippedTest(module: $0.module, suite: $0.suite, name: $0.name) }
                ))
            }
        case let .badRequest(response):
            switch response.body {
            case let .json(error): return .failed(error.message)
            }
        case let .unauthorized(response):
            switch response.body {
            case let .json(error): return .failed(error.message)
            }
        case let .forbidden(response):
            switch response.body {
            case let .json(error): return .failed(error.message)
            }
        case let .notFound(response):
            switch response.body {
            case let .json(error): return .failed(error.message)
            }
        case let .tooManyRequests(response):
            switch response.body {
            case let .json(error): return .failed(error.message)
            }
        case let .undocumented(statusCode, _):
            return .failed("The test impact run request failed with an unknown Tuist response of \(statusCode).")
        }
    }
}
