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

/// Decides which tests of the targets left after hash pruning run, through the server's
/// coverage-based test selection, and keeps the outcome for the run. It's consulted by
/// `TestImpactGraphMapper` while the project is generated, so that modules with no selected test are
/// pruned before anything is built.
///
/// Before it asks for a baseline it publishes the run's Git history, so the server's graph has the
/// checkout's commit when it places it.
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
        /// Whether the run uploads coverage (`UploadResultBundleService.uploadsCoverage`), as the run's
        /// report tells `GitHistoryService`.
        let coverage: Bool
    }

    /// How many of the checkout's ancestors the server accepts.
    static let ancestorLimit = 200

    let invocation: Invocation
    private(set) var outcome: TestImpactOutcome?

    private let gitController: GitControlling
    private let resolveBaselineService: ResolveTestImpactBaselineServicing
    private let createRunService: CreateTestImpactRunServicing
    private let gitHistoryService: GitHistoryServicing
    /// Whether the run reports without credentials, which uploads no history.
    private let reportsWithoutCredentials: @Sendable (URL) async -> Bool

    init(
        invocation: Invocation,
        gitController: GitControlling = GitController(),
        resolveBaselineService: ResolveTestImpactBaselineServicing = ResolveTestImpactBaselineService(),
        createRunService: CreateTestImpactRunServicing = CreateTestImpactRunService(),
        gitHistoryService: GitHistoryServicing = GitHistoryService(),
        reportsWithoutCredentials: @escaping @Sendable (URL) async -> Bool = {
            // Rejected credentials fail the report too, so nothing is uploaded ahead of it.
            (try? await ServerReportPublishingMode.usesNetworkTrust(serverURL: $0)) ?? true
        }
    ) {
        self.invocation = invocation
        self.gitController = gitController
        self.resolveBaselineService = resolveBaselineService
        self.createRunService = createRunService
        self.gitHistoryService = gitHistoryService
        self.reportsWithoutCredentials = reportsWithoutCredentials
    }

    // swiftlint:disable function_body_length

    /// Selects the tests of `modules`, the test targets hashing left, and returns the modules to prune
    /// because none of their tests was selected. Whatever the server answers, what runs is what hashing
    /// left minus what the run skips: a fallback prunes nothing. When hashing left no module, the run
    /// is still recorded, so the server counts what hashing skipped.
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
    ) async -> Set<String> {
        guard outcome == nil, !modules.isEmpty || !skippedModules.isEmpty,
              await gitController.isInGitRepository(workingDirectory: invocation.path)
        else {
            return []
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
            return []
        }

        await publishGitHistory(gitInfo: gitInfo, repository: repository)

        let refs = Self.deepeningRefs(gitInfo: gitInfo)
        var ancestorSHAs: [String] = []
        var baseline = await resolveBaseline(checkout: checkout, ancestorSHAs: ancestorSHAs, platform: platform)
        // The checkout may still lead to the server's history only through commits it hasn't seen,
        // when the history couldn't be published or the publish is off: the server then walks from
        // the checkout's ancestors. A clone is deepened at most once per invocation, so the diff below
        // doesn't deepen again.
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
            return []
        case let .failed(message):
            warn(message)
            return []
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
        switch result {
        case let .selected(selection):
            let unselectedModules = Set(TestImpactSkipList(selection.skippedTests).modules).intersection(modules)
            outcome = .selected(selection, skippedModules: unselectedModules.sorted())
            return unselectedModules
        case let .fallback(runID, reason, matchedPath):
            outcome = .fallback(runID: runID, reason: reason, matchedPath: matchedPath)
            return []
        case let .failed(message):
            warn(message)
            return []
        }
    }

    // swiftlint:enable function_body_length

    /// Uploads the commits and branch heads the server's graph lacks, so the baseline request finds the
    /// checkout's commit, or on a pull request's merge checkout both its parents, in the graph: the
    /// history `GitHistoryService` collects is the commit `gitInfo` reports, never the merge commit.
    /// The collection and the upload are kept per process under the repository's top level, the
    /// directory the report reads the history from too, so the report sends nothing again. A failed
    /// upload only warns, as the report's does, and is retried when the run is reported.
    private func publishGitHistory(gitInfo: GitInfo, repository: AbsolutePath) async {
        guard await !reportsWithoutCredentials(invocation.serverURL) else { return }
        _ = await gitHistoryService.publish(
            gitInfo: gitInfo,
            workingDirectory: repository,
            fullHandle: invocation.fullHandle,
            serverURL: invocation.serverURL,
            coverage: invocation.coverage
        )
    }

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
