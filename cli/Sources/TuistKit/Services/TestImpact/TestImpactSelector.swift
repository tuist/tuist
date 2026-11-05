import Foundation
import Path
import TuistAlert
import TuistGit
import TuistLogging
import TuistServer
import XcodeGraph

/// What coverage-based test selection decided for one `tuist test` invocation, for the run to
/// apply, print and upload.
enum TestImpactOutcome: Equatable {
    /// Coverage selected tests. `skippedModules` are the modules none of whose tests was selected,
    /// pruned from the generated project so they aren't built.
    case selected(TestImpactSelection, skippedModules: [String])
    /// The server recorded a fallback, so the run uploads with `runID`.
    case fallback(runID: String, reason: TestImpactFallbackReason?, matchedPath: String?)

    var runID: String {
        switch self {
        case let .selected(selection, _): selection.runID
        case let .fallback(runID, _, _): runID
        }
    }

    var skippedModules: [String] {
        guard case let .selected(_, skippedModules) = self else { return [] }
        return skippedModules
    }

    /// The tests to skip, nil on a fallback.
    var skipList: TestImpactSkipList? {
        guard case let .selected(selection, _) = self else { return nil }
        return TestImpactSkipList(selection.skippedTests)
    }
}

/// How the generated graph changes after selection.
enum TestImpactGraphDecision: Equatable {
    /// Default selective testing: the targets hashing left run.
    case unchanged
    /// Every test target in scope runs, those whose hash matched included, so the commit can serve
    /// as a baseline.
    case runAll
    /// The modules to prune: none of their tests was selected.
    case prune(Set<String>)
}

/// Decides which tests of the targets left after hash pruning run, through the server's
/// coverage-based test selection, and keeps the outcome for the run. It's consulted by
/// `TestImpactGraphMapper` while the project is generated, so that modules with no selected test are
/// pruned before anything is built.
///
/// It never fails the run: a request that fails or times out leaves default selective testing, with a
/// warning.
actor TestImpactSelector {
    /// The selector for the invocation being generated, nil when selection is off.
    @TaskLocal static var current: TestImpactSelector?

    struct Invocation: Equatable {
        let fullHandle: String
        let serverURL: URL
        /// Where the project is, inside the repository whose history is diffed.
        let path: AbsolutePath
        let scheme: String?
        let testPlan: String?
        /// The `-destination` passed to xcodebuild, if any.
        let destination: String?
        /// The platform the run asked for, through `--platform` or `-destination`.
        let platform: XcodeGraph.Platform?
    }

    /// How many of the checkout's ancestors the server accepts.
    static let ancestorLimit = 200

    /// The reasons after which every test target in scope runs, so that the commit becomes a
    /// baseline for later runs.
    static let runAllReasons: Set<TestImpactFallbackReason> = [.noBaseline, .baselineTooOld, .diffTooLarge]

    let invocation: Invocation
    private(set) var outcome: TestImpactOutcome?

    private let gitController: GitControlling
    private let resolveBaselineService: ResolveTestImpactBaselineServicing
    private let createRunService: CreateTestImpactRunServicing

    init(
        invocation: Invocation,
        gitController: GitControlling = GitController(),
        resolveBaselineService: ResolveTestImpactBaselineServicing = ResolveTestImpactBaselineService(),
        createRunService: CreateTestImpactRunServicing = CreateTestImpactRunService()
    ) {
        self.invocation = invocation
        self.gitController = gitController
        self.resolveBaselineService = resolveBaselineService
        self.createRunService = createRunService
    }

    // swiftlint:disable function_body_length

    /// Selects the tests of `modules`, the test targets hashing left. When hashing left none, the run
    /// is still recorded, so the server counts what hashing skipped, and the graph stays unchanged
    /// whatever the server answers: coverage never runs more than hashing alone.
    /// - Parameters:
    ///   - modules: The test modules left to decide; empty when every target's hash matched.
    ///   - skippedModules: The test modules hashing skipped.
    ///   - platform: The platform the tests run on, which the baseline must match.
    ///   - affectedModules: The test modules a changed file, by absolute path, can affect: empty when
    ///     no target owns it, nil when it can't be classified.
    func decide(
        modules: [String],
        skippedModules: [String],
        platform: String?,
        affectedModules: @Sendable (AbsolutePath) -> [String]?
    ) async -> TestImpactGraphDecision {
        guard outcome == nil, !modules.isEmpty || !skippedModules.isEmpty,
              await gitController.isInGitRepository(workingDirectory: invocation.path)
        else {
            return .unchanged
        }
        let repository: AbsolutePath
        let gitInfo: GitInfo
        let checkout: GitCheckedOutCommit
        do {
            repository = try await gitController.topLevelGitDirectory(workingDirectory: invocation.path)
            gitInfo = try await gitController.gitInfo(workingDirectory: repository)
            checkout = try await gitController.checkedOutCommit(workingDirectory: repository)
        } catch {
            warn("the checkout couldn't be read: \(error.localizedDescription)")
            return .unchanged
        }

        let refs = Self.deepeningRefs(gitInfo: gitInfo)
        var ancestorSHAs: [String] = []
        var baseline = await resolveBaseline(checkout: checkout, ancestorSHAs: ancestorSHAs, platform: platform)
        // The checkout may lead to the server's history only through commits it hasn't seen, such as
        // a push of several commits: the server then walks from the checkout's ancestors. A clone is
        // deepened at most once per invocation, so the diff below doesn't deepen again.
        var deepeningRefs = refs
        if baseline == .unavailable(.historyUnknown) {
            _ = await gitController.deepenShallowClone(workingDirectory: repository, refs: refs, limits: Self.historyLimits)
            deepeningRefs = []
            ancestorSHAs = await gitController.ancestorSHAs(workingDirectory: repository, limit: Self.ancestorLimit)
            baseline = await resolveBaseline(checkout: checkout, ancestorSHAs: ancestorSHAs, platform: platform)
        }

        let basis: TestImpactRunRequest.Basis
        switch baseline {
        case .notEnabled:
            return .unchanged
        case let .failed(message):
            warn(message)
            return .unchanged
        case let .unavailable(reason):
            basis = .fallback(reason)
        case let .baseline(sha, _) where modules.isEmpty:
            // Nothing is left to decide, so there's nothing to diff.
            basis = .baseline(sha: sha, changedFiles: nil, dirty: false)
        case let .baseline(sha, diffCached):
            basis = await diffBasis(
                baselineSHA: sha,
                diffCached: diffCached,
                repository: repository,
                deepening: deepeningRefs,
                affectedModules: affectedModules
            )
        }

        let request = TestImpactRunRequest(
            headSHA: gitInfo.sha ?? checkout.sha,
            commitSHA: checkout.sha == gitInfo.sha ? nil : checkout.sha,
            parentSHAs: checkout.parentSHAs,
            ancestorSHAs: ancestorSHAs,
            basis: basis,
            modules: modules,
            skippedModules: skippedModules,
            platform: platform,
            gitBranch: gitInfo.branch,
            scheme: invocation.scheme,
            testPlan: invocation.testPlan,
            destination: invocation.destination
        )
        let result = await createRunService.createTestImpactRun(
            fullHandle: invocation.fullHandle,
            serverURL: invocation.serverURL,
            request: request
        )
        // The run only records what hashing skipped: no outcome, so nothing plans shards from it.
        if modules.isEmpty {
            if case let .failed(message) = result { warn(message) }
            return .unchanged
        }
        switch result {
        case let .selected(selection):
            let unselectedModules = Set(TestImpactSkipList(selection.skippedTests).modules).intersection(modules)
            outcome = .selected(selection, skippedModules: unselectedModules.sorted())
            return .prune(unselectedModules)
        case let .fallback(runID, reason, matchedPath):
            outcome = .fallback(runID: runID, reason: reason, matchedPath: matchedPath)
            return reason.map(Self.runAllReasons.contains) == true ? .runAll : .unchanged
        case let .failed(message):
            warn(message)
            return .unchanged
        }
    }

    // swiftlint:enable function_body_length

    private func resolveBaseline(
        checkout: GitCheckedOutCommit,
        ancestorSHAs: [String],
        platform: String?
    ) async -> TestImpactBaselineResolution {
        await resolveBaselineService.resolveTestImpactBaseline(
            fullHandle: invocation.fullHandle,
            serverURL: invocation.serverURL,
            commitSHA: checkout.sha,
            parentSHAs: checkout.parentSHAs,
            ancestorSHAs: ancestorSHAs,
            platform: platform,
            scheme: invocation.scheme,
            testPlan: invocation.testPlan,
            destination: invocation.destination
        )
    }

    /// What deepening may read from the remote: the history coverage needs, unless
    /// `TUIST_GIT_UNSHALLOW_ENABLED=false` keeps runs to what the checkout has.
    private static var historyLimits: GitHistoryLimits {
        GitHistoryLimits(remoteAccess: GitHistoryService.remoteAccess(coverage: true))
    }

    /// The remote refs whose history leads from the checkout to a baseline.
    private static func deepeningRefs(gitInfo: GitInfo) -> [String] {
        [gitInfo.ref?.hasPrefix("refs/pull/") == true ? gitInfo.ref : nil, gitInfo.baseBranch ?? gitInfo.branch]
            .compactMap { $0 }
    }

    private func diffBasis(
        baselineSHA: String,
        diffCached: Bool,
        repository: AbsolutePath,
        deepening refs: [String],
        affectedModules: (AbsolutePath) -> [String]?
    ) async -> TestImpactRunRequest.Basis {
        // A dirty checkout's diff is its own, so the server never has it.
        let dirty = (try? await gitController.hasUncommittedChanges(workingDirectory: repository)) ?? true
        if diffCached, !dirty {
            return .baseline(sha: baselineSHA, changedFiles: nil, dirty: false)
        }
        do {
            switch try await gitController.changedFiles(
                workingDirectory: repository,
                since: baselineSHA,
                deepening: refs,
                limits: Self.historyLimits
            ) {
            case let .historyUnavailable(reason):
                Logger.current.debug("Coverage-based test selection has no history to diff: \(reason)")
                return .fallback(.historyUnavailable)
            case let .changed(changes):
                return .baseline(
                    sha: baselineSHA,
                    changedFiles: changes.files.map {
                        TestImpactChangedFile(
                            path: $0.path,
                            status: $0.status,
                            blob: $0.blobId,
                            affectedModules: (try? RelativePath(validating: $0.path)).flatMap {
                                affectedModules(repository.appending($0))
                            }
                        )
                    },
                    dirty: changes.dirty
                )
            }
        } catch {
            Logger.current.debug("Coverage-based test selection couldn't diff the checkout: \(error.localizedDescription)")
            return .fallback(.historyUnavailable)
        }
    }

    private func warn(_ message: String) {
        AlertController.current.warning(.alert(
            "Coverage-based test selection is unavailable, running default selective testing: \(message)"
        ))
    }
}
