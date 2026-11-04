import Foundation

/// Why coverage-based test selection fell back to default selective testing. The server sends these
/// as plain strings so it can add reasons without breaking older clients, which keep the raw value.
public struct TestImpactFallbackReason: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    /// The run is on the project's default branch, which never selects.
    public static let excludedBranch = TestImpactFallbackReason(rawValue: "excluded_branch")
    /// More changed files than the server analyzes.
    public static let diffTooLarge = TestImpactFallbackReason(rawValue: "diff_too_large")
    /// No full run in reach on the platform.
    public static let noBaseline = TestImpactFallbackReason(rawValue: "no_baseline")
    /// The nearest full run is past the evidence window.
    public static let baselineTooOld = TestImpactFallbackReason(rawValue: "baseline_too_old")
    /// The baseline uploaded no test-scoped evidence.
    public static let noBaselineEvidence = TestImpactFallbackReason(rawValue: "no_baseline_evidence")
    /// The server's history has neither the checked-out commit nor its parents, so the walk to a
    /// baseline can't start.
    public static let historyUnknown = TestImpactFallbackReason(rawValue: "history_unknown")
    /// Deepening the checkout didn't reach the baseline within its budget.
    public static let historyUnavailable = TestImpactFallbackReason(rawValue: "history_unavailable")
    /// A file whose change can affect any test without showing up in coverage changed.
    public static let trackedFileChanged = TestImpactFallbackReason(rawValue: "tracked_file_changed")
    /// Test impact analysis isn't enabled for the project.
    public static let notEnabled = TestImpactFallbackReason(rawValue: "not_enabled")

    /// The reasons the baseline request returns that still create an impact run, so the server
    /// records the fallback.
    static let recordedBaselineReasons: Set<TestImpactFallbackReason> = [
        .noBaseline, .baselineTooOld, .noBaselineEvidence, .historyUnknown,
    ]
}

/// What the baseline request decided.
public enum TestImpactBaselineResolution: Equatable, Sendable {
    /// The commit to diff the checkout against, and whether the server already stores that diff,
    /// in which case the client neither deepens nor diffs.
    case baseline(sha: String, diffCached: Bool)
    /// There's no baseline. The client still creates the impact run, with this reason, so the server
    /// records the fallback.
    case unavailable(TestImpactFallbackReason)
    /// Selection is off for the project, or the server sent a reason this client doesn't know: the
    /// client runs default selective testing and makes no further selection call.
    case notEnabled
    /// The request failed or timed out: default selective testing, with a warning and no impact run.
    case failed(String)
}

/// A changed file as the runs request sends it.
public struct TestImpactChangedFile: Equatable, Sendable {
    /// The repository-relative path.
    public let path: String
    /// The change, as `git diff --raw` reports it (`A`, `M`, `D`, `T`).
    public let status: String
    /// The file's blob in the checkout; nil only for deleted files.
    public let blob: String?
    /// The test modules the file can affect. Empty when no target owns it, nil when it couldn't be
    /// classified.
    public let affectedModules: [String]?

    public init(path: String, status: String, blob: String?, affectedModules: [String]?) {
        self.path = path
        self.status = status
        self.blob = blob
        self.affectedModules = affectedModules
    }
}

/// What one `tuist test` invocation sends to decide its tests.
public struct TestImpactRunRequest: Equatable, Sendable {
    public enum Basis: Equatable, Sendable {
        /// The baseline the baseline request returned, with the diff when the server doesn't have it
        /// yet, and whether the checkout had dirty or untracked files.
        case baseline(sha: String, changedFiles: [TestImpactChangedFile]?, dirty: Bool)
        /// Why there's no baseline to select against: the baseline request's reason, or
        /// `history_unavailable`.
        case fallback(TestImpactFallbackReason)
    }

    public let buildSystem: String
    /// The pull request head, or the checked-out commit outside pull requests.
    public let headSHA: String
    /// The commit the diff ran against, such as GitHub's synthetic merge commit, when it isn't the head.
    public let commitSHA: String?
    /// The checked-out commit's parents when it's a pull request's merge commit, as sent to the
    /// baseline request, so the server resolves the same baseline.
    public let parentSHAs: [String]
    public let basis: Basis
    /// The test modules left to decide, nil when nothing narrowed the scope.
    public let modules: [String]?
    public let platform: String?
    public let gitBranch: String?
    public let scheme: String?
    public let testPlan: String?
    public let destination: String?

    public init(
        buildSystem: String = "xcode",
        headSHA: String,
        commitSHA: String?,
        parentSHAs: [String] = [],
        basis: Basis,
        modules: [String]?,
        platform: String?,
        gitBranch: String?,
        scheme: String?,
        testPlan: String?,
        destination: String?
    ) {
        self.buildSystem = buildSystem
        self.headSHA = headSHA
        self.commitSHA = commitSHA
        self.parentSHAs = parentSHAs
        self.basis = basis
        self.modules = modules
        self.platform = platform
        self.gitBranch = gitBranch
        self.scheme = scheme
        self.testPlan = testPlan
        self.destination = destination
    }
}

/// A test not to run. Only `module` is set when none of the module's tests is selected.
public struct SkippedTest: Equatable, Hashable, Sendable {
    public let module: String
    public let suite: String?
    public let name: String?

    public init(module: String, suite: String?, name: String?) {
        self.module = module
        self.suite = suite
        self.name = name
    }
}

/// The tests coverage selected for an invocation.
public struct TestImpactSelection: Equatable, Sendable {
    public let runID: String
    public let requested: Int?
    public let selected: Int?
    public let skipped: Int?
    /// The tests not to run, empty for sharded runs, which read theirs from the shard.
    public let skippedTests: [SkippedTest]

    public init(runID: String, requested: Int?, selected: Int?, skipped: Int?, skippedTests: [SkippedTest]) {
        self.runID = runID
        self.requested = requested
        self.selected = selected
        self.skipped = skipped
        self.skippedTests = skippedTests
    }
}

/// What the runs request decided.
public enum TestImpactRunOutcome: Equatable, Sendable {
    case selected(TestImpactSelection)
    /// The server recorded a fallback: default selective testing, uploading with `runID`.
    case fallback(runID: String, reason: TestImpactFallbackReason?, matchedPath: String?)
    /// The request failed or timed out: default selective testing, with a warning and no impact run.
    case failed(String)
}

/// Selection blocks the build, so a request that outlasts `timeout` is abandoned and the run falls
/// back. Returns nil on timeout.
public func withTestImpactTimeout<T: Sendable>(
    _ timeout: Duration,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T? {
    try await withThrowingTaskGroup(of: T?.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: timeout)
            return nil
        }
        defer { group.cancelAll() }
        return try await group.next() ?? nil
    }
}
