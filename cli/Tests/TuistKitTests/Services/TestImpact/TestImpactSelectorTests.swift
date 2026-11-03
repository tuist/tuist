import Foundation
import Mockable
import Path
import Testing
import TuistGit
import TuistServer
@testable import TuistKit

struct TestImpactSelectorTests {
    private let gitController = MockGitControlling()
    private let getProjectService = MockGetProjectServicing()
    private let resolveBaselineService = MockResolveTestImpactBaselineServicing()
    private let createRunService = MockCreateTestImpactRunServicing()
    private let repository = try! AbsolutePath(validating: "/repo")
    private let serverURL = URL(string: "https://tuist.dev")!
    private let subject: TestImpactSelector

    init() {
        subject = TestImpactSelector(
            invocation: TestImpactSelector.Invocation(
                fullHandle: "acme/shop",
                serverURL: serverURL,
                path: repository.appending(component: "App"),
                scheme: "Shop",
                testPlan: nil,
                destination: "platform=iOS Simulator,name=iPhone 17",
                platform: .iOS
            ),
            gitController: gitController,
            getProjectService: getProjectService,
            resolveBaselineService: resolveBaselineService,
            createRunService: createRunService
        )
        given(gitController).isInGitRepository(workingDirectory: .any).willReturn(true)
        given(gitController).topLevelGitDirectory(workingDirectory: .any).willReturn(repository)
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
    }

    @Test func prunes_the_modules_with_no_selected_test() async throws {
        givenPullRequestCheckout()
        givenBaseline(.baseline(sha: "baseline", diffCached: false))
        given(gitController)
            .changedFiles(workingDirectory: .any, since: .any, deepening: .any, limits: .any)
            .willReturn(.changed(GitChangedFiles(
                files: [
                    GitChangedFile(path: "Core/Discount.swift", status: "M", blobId: "blob"),
                    GitChangedFile(path: "README.md", status: "M", blobId: "readme"),
                ],
                dirty: false
            )))
        let selection = TestImpactSelection(
            runID: "run",
            requested: 6,
            selected: 2,
            skipped: 4,
            skippedTests: [
                SkippedTest(module: "CatalogTests", suite: nil, name: nil),
                SkippedTest(module: "CoreTests", suite: "MoneyTests", name: "testAdd()"),
                SkippedTest(module: "OutOfScopeTests", suite: nil, name: nil),
            ]
        )
        given(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any)
            .willReturn(.selected(selection))

        let decision = await subject.decide(modules: ["CatalogTests", "CoreTests"], platform: "ios") { path in
            path.basename == "Discount.swift" ? ["CoreTests"] : []
        }

        #expect(decision == .prune(["CatalogTests"]))
        #expect(await subject.outcome == .selected(selection, skippedModules: ["CatalogTests"]))
        verify(gitController)
            .changedFiles(
                workingDirectory: .value(repository),
                since: .value("baseline"),
                deepening: .value(["refs/pull/7/merge", "main"]),
                limits: .any
            )
            .called(1)
        verify(createRunService).createTestImpactRun(
            fullHandle: .value("acme/shop"),
            serverURL: .value(serverURL),
            request: .value(TestImpactRunRequest(
                headSHA: "head",
                commitSHA: "merge",
                parentSHAs: ["main-tip", "head"],
                basis: .baseline(
                    sha: "baseline",
                    changedFiles: [
                        TestImpactChangedFile(
                            path: "Core/Discount.swift",
                            status: "M",
                            blob: "blob",
                            affectedModules: ["CoreTests"]
                        ),
                        TestImpactChangedFile(path: "README.md", status: "M", blob: "readme", affectedModules: []),
                    ],
                    dirty: false
                ),
                modules: ["CatalogTests", "CoreTests"],
                platform: "ios",
                gitBranch: "feature",
                scheme: "Shop",
                testPlan: nil,
                destination: "platform=iOS Simulator,name=iPhone 17"
            ))
        ).called(1)
        verify(getProjectService).getProject(fullHandle: .any, serverURL: .any).called(0)
    }

    @Test func reuses_the_diff_the_server_has() async throws {
        givenPullRequestCheckout()
        givenBaseline(.baseline(sha: "baseline", diffCached: true))
        given(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any)
            .willReturn(.fallback(runID: "run", reason: .trackedFileChanged, matchedPath: "Package.resolved"))

        let decision = await subject.decide(modules: ["CoreTests"], platform: "ios") { _ in [] }

        #expect(decision == .unchanged)
        #expect(await subject.outcome == .fallback(runID: "run", reason: .trackedFileChanged, matchedPath: "Package.resolved"))
        verify(gitController).changedFiles(workingDirectory: .any, since: .any, deepening: .any, limits: .any).called(0)
        verify(createRunService).createTestImpactRun(
            fullHandle: .any,
            serverURL: .any,
            request: .matching { $0.basis == .baseline(sha: "baseline", changedFiles: nil, dirty: false) }
        ).called(1)
    }

    @Test func does_nothing_more_when_selection_is_not_enabled() async throws {
        givenPullRequestCheckout()
        givenBaseline(.notEnabled)

        let decision = await subject.decide(modules: ["CoreTests"], platform: "ios") { _ in [] }

        #expect(decision == .unchanged)
        #expect(await subject.outcome == nil)
        verify(gitController).changedFiles(workingDirectory: .any, since: .any, deepening: .any, limits: .any).called(0)
        verify(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any).called(0)
    }

    @Test func records_a_missing_baseline_and_runs_every_test() async throws {
        givenPullRequestCheckout()
        givenBaseline(.unavailable(.noBaseline))
        given(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any)
            .willReturn(.fallback(runID: "run", reason: .noBaseline, matchedPath: nil))

        let decision = await subject.decide(modules: ["CoreTests"], platform: "ios") { _ in [] }

        #expect(decision == .runAll)
        verify(createRunService).createTestImpactRun(
            fullHandle: .any,
            serverURL: .any,
            request: .matching { $0.basis == .fallback(.noBaseline) }
        ).called(1)
    }

    @Test func records_history_unavailable_when_deepening_falls_short() async throws {
        givenPullRequestCheckout()
        givenBaseline(.baseline(sha: "baseline", diffCached: false))
        given(gitController)
            .changedFiles(workingDirectory: .any, since: .any, deepening: .any, limits: .any)
            .willReturn(.historyUnavailable("shallow clone"))
        given(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any)
            .willReturn(.fallback(runID: "run", reason: .historyUnavailable, matchedPath: nil))

        let decision = await subject.decide(modules: ["CoreTests"], platform: "ios") { _ in [] }

        #expect(decision == .unchanged)
        verify(createRunService).createTestImpactRun(
            fullHandle: .any,
            serverURL: .any,
            request: .matching { $0.basis == .fallback(.historyUnavailable) }
        ).called(1)
    }

    @Test func keeps_default_selective_testing_when_the_run_request_fails() async throws {
        givenPullRequestCheckout()
        givenBaseline(.baseline(sha: "baseline", diffCached: true))
        given(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any)
            .willReturn(.failed("timed out"))

        let decision = await subject.decide(modules: ["CoreTests"], platform: "ios") { _ in [] }

        #expect(decision == .unchanged)
        #expect(await subject.outcome == nil)
    }

    @Test func makes_no_call_when_every_target_matched_its_hash() async throws {
        givenPullRequestCheckout()
        let decision = await subject.decide(modules: [], platform: "ios") { _ in [] }

        #expect(decision == .unchanged)
        verify(resolveBaselineService).resolveTestImpactBaseline(
            fullHandle: .any, serverURL: .any, commitSHA: .any, parentSHAs: .any,
            platform: .any, scheme: .any, testPlan: .any, destination: .any
        ).called(0)
    }

    @Test func records_the_default_branch_and_runs_every_test() async throws {
        givenDefaultBranchCheckout()
        givenBaseline(.baseline(sha: "older", diffCached: false))
        given(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any)
            .willReturn(.fallback(runID: "run", reason: .excludedBranch, matchedPath: nil))

        let decision = await subject.decide(modules: [], platform: "ios") { _ in [] }

        #expect(decision == .runAll)
        verify(gitController).changedFiles(workingDirectory: .any, since: .any, deepening: .any, limits: .any).called(0)
        verify(createRunService).createTestImpactRun(
            fullHandle: .any,
            serverURL: .any,
            request: .matching { $0.basis == .fallback(.excludedBranch) && $0.commitSHA == nil }
        ).called(1)
    }

    @Test func keeps_hash_pruning_on_the_default_branch_when_selection_is_not_enabled() async throws {
        givenDefaultBranchCheckout()
        givenBaseline(.notEnabled)

        let decision = await subject.decide(modules: ["CoreTests"], platform: "ios") { _ in [] }

        #expect(decision == .unchanged)
        verify(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any).called(0)
    }

    @Test func reads_the_platform_off_an_xcodebuild_destination() {
        #expect(TestImpactSelector.platform(xcodebuildDestination: "platform=iOS Simulator,name=iPhone 17") == .iOS)
        #expect(TestImpactSelector.platform(xcodebuildDestination: "generic/platform=tvOS") == .tvOS)
        #expect(TestImpactSelector.platform(xcodebuildDestination: "platform=macOS,arch=arm64") == .macOS)
        #expect(TestImpactSelector.platform(xcodebuildDestination: "id=1234") == nil)
    }

    /// A pull request's merge commit, as GitHub Actions checks it out.
    private func givenPullRequestCheckout() {
        given(gitController).gitInfo(workingDirectory: .any).willReturn(.test(
            ref: "refs/pull/7/merge",
            branch: "feature",
            sha: "head",
            baseBranch: "main",
            pullRequestNumber: 7
        ))
        given(gitController).checkedOutCommit(workingDirectory: .any)
            .willReturn(GitCheckedOutCommit(sha: "merge", parentSHAs: ["main-tip", "head"]))
    }

    private func givenDefaultBranchCheckout() {
        given(gitController).gitInfo(workingDirectory: .any)
            .willReturn(.test(ref: "refs/heads/main", branch: "main", sha: "main-tip"))
        given(gitController).checkedOutCommit(workingDirectory: .any)
            .willReturn(GitCheckedOutCommit(sha: "main-tip", parentSHAs: []))
        given(getProjectService).getProject(fullHandle: .any, serverURL: .any)
            .willReturn(.test(defaultBranch: "main"))
    }

    private func givenBaseline(_ resolution: TestImpactBaselineResolution) {
        given(resolveBaselineService).resolveTestImpactBaseline(
            fullHandle: .any, serverURL: .any, commitSHA: .any, parentSHAs: .any,
            platform: .any, scheme: .any, testPlan: .any, destination: .any
        ).willReturn(resolution)
    }
}
