import Foundation
import Mockable
import Path
import Testing
import TuistGit
import TuistServer
@testable import TuistKit

struct TestImpactSelectorTests {
    private let gitController = MockGitControlling()
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
            resolveBaselineService: resolveBaselineService,
            createRunService: createRunService
        )
        given(gitController).isInGitRepository(workingDirectory: .any).willReturn(true)
        given(gitController).topLevelGitDirectory(workingDirectory: .any).willReturn(repository)
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
        given(gitController).deepenShallowClone(workingDirectory: .any, refs: .any, limits: .any).willReturn(true)
        given(gitController).ancestorSHAs(workingDirectory: .any, limit: .any).willReturn(["parent", "grandparent"])
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
        verify(resolveBaselineService).resolveTestImpactBaseline(
            fullHandle: .any, serverURL: .any, commitSHA: .value("merge"), parentSHAs: .value(["main-tip", "head"]),
            ancestorSHAs: .value([]),
            platform: .any, scheme: .any, testPlan: .any, destination: .any
        ).called(1)
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
        // The server knew the checkout's parents, so nothing deepened and no ancestors were sent.
        verify(gitController).deepenShallowClone(workingDirectory: .any, refs: .any, limits: .any).called(0)
        verify(gitController).ancestorSHAs(workingDirectory: .any, limit: .any).called(0)
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
        verify(gitController).deepenShallowClone(workingDirectory: .any, refs: .any, limits: .any).called(0)
        verify(createRunService).createTestImpactRun(
            fullHandle: .any,
            serverURL: .any,
            request: .matching { $0.basis == .baseline(sha: "baseline", changedFiles: nil, dirty: false) }
        ).called(1)
    }

    @Test func deepens_once_and_asks_again_with_the_ancestors_when_the_server_doesnt_know_the_history() async throws {
        givenPullRequestCheckout()
        final class Requests {
            var count = 0
        }
        let requests = Requests()
        given(resolveBaselineService).resolveTestImpactBaseline(
            fullHandle: .any, serverURL: .any, commitSHA: .any, parentSHAs: .any, ancestorSHAs: .any,
            platform: .any, scheme: .any, testPlan: .any, destination: .any
        ).willProduce { _, _, _, _, _, _, _, _, _ in
            requests.count += 1
            return requests.count == 1 ? .unavailable(.historyUnknown) : .baseline(sha: "baseline", diffCached: false)
        }
        given(gitController)
            .changedFiles(workingDirectory: .any, since: .any, deepening: .any, limits: .any)
            .willReturn(.changed(GitChangedFiles(files: [], dirty: false)))
        given(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any)
            .willReturn(.fallback(runID: "run", reason: .trackedFileChanged, matchedPath: "Package.resolved"))

        _ = await subject.decide(modules: ["CoreTests"], platform: "ios") { _ in [] }

        verify(gitController)
            .deepenShallowClone(workingDirectory: .value(repository), refs: .value(["refs/pull/7/merge", "main"]), limits: .any)
            .called(1)
        verify(gitController).ancestorSHAs(workingDirectory: .value(repository), limit: .value(200)).called(1)
        verify(resolveBaselineService).resolveTestImpactBaseline(
            fullHandle: .any, serverURL: .any, commitSHA: .any, parentSHAs: .any, ancestorSHAs: .value([]),
            platform: .any, scheme: .any, testPlan: .any, destination: .any
        ).called(1)
        verify(resolveBaselineService).resolveTestImpactBaseline(
            fullHandle: .any, serverURL: .any, commitSHA: .any, parentSHAs: .any, ancestorSHAs: .value(["parent", "grandparent"]),
            platform: .any, scheme: .any, testPlan: .any, destination: .any
        ).called(1)
        // The clone was already deepened once, so the diff doesn't deepen again.
        verify(gitController)
            .changedFiles(workingDirectory: .any, since: .value("baseline"), deepening: .value([]), limits: .any)
            .called(1)
        verify(createRunService).createTestImpactRun(
            fullHandle: .any,
            serverURL: .any,
            request: .matching {
                $0.basis == .baseline(sha: "baseline", changedFiles: [], dirty: false) && $0.ancestorSHAs == [
                    "parent",
                    "grandparent",
                ]
            }
        ).called(1)
    }

    @Test func falls_back_when_the_server_still_doesnt_know_the_history() async throws {
        givenPullRequestCheckout()
        givenBaseline(.unavailable(.historyUnknown))
        given(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any)
            .willReturn(.fallback(runID: "run", reason: .historyUnknown, matchedPath: nil))

        _ = await subject.decide(modules: ["CoreTests"], platform: "ios") { _ in [] }

        verify(gitController).deepenShallowClone(workingDirectory: .any, refs: .any, limits: .any).called(1)
        verify(resolveBaselineService).resolveTestImpactBaseline(
            fullHandle: .any, serverURL: .any, commitSHA: .any, parentSHAs: .any, ancestorSHAs: .any,
            platform: .any, scheme: .any, testPlan: .any, destination: .any
        ).called(2)
        verify(gitController).changedFiles(workingDirectory: .any, since: .any, deepening: .any, limits: .any).called(0)
        verify(createRunService).createTestImpactRun(
            fullHandle: .any,
            serverURL: .any,
            request: .matching { $0.basis == .fallback(.historyUnknown) && $0.ancestorSHAs == ["parent", "grandparent"] }
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

    @Test(arguments: [true, false])
    func makes_no_call_when_every_target_matched_its_hash(pullRequest: Bool) async throws {
        if pullRequest { givenPullRequestCheckout() } else { givenBranchCheckout() }

        let decision = await subject.decide(modules: [], platform: "ios") { _ in [] }

        #expect(decision == .unchanged)
        verify(resolveBaselineService).resolveTestImpactBaseline(
            fullHandle: .any, serverURL: .any, commitSHA: .any, parentSHAs: .any, ancestorSHAs: .any,
            platform: .any, scheme: .any, testPlan: .any, destination: .any
        ).called(0)
        verify(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any).called(0)
    }

    @Test func selects_on_a_branch_push_and_records_the_branch() async throws {
        givenBranchCheckout()
        givenBaseline(.baseline(sha: "older", diffCached: true))
        given(createRunService).createTestImpactRun(fullHandle: .any, serverURL: .any, request: .any)
            .willReturn(.fallback(runID: "run", reason: .trackedFileChanged, matchedPath: "Package.resolved"))

        let decision = await subject.decide(modules: ["CoreTests"], platform: "ios") { _ in [] }

        #expect(decision == .unchanged)
        verify(createRunService).createTestImpactRun(
            fullHandle: .any,
            serverURL: .any,
            request: .matching {
                $0.basis == .baseline(sha: "older", changedFiles: nil, dirty: false) && $0.commitSHA == nil
                    && $0.parentSHAs == ["main-parent"] && $0.gitBranch == "main"
            }
        ).called(1)
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

    private func givenBranchCheckout() {
        given(gitController).gitInfo(workingDirectory: .any)
            .willReturn(.test(ref: "refs/heads/main", branch: "main", sha: "main-tip"))
        given(gitController).checkedOutCommit(workingDirectory: .any)
            .willReturn(GitCheckedOutCommit(sha: "main-tip", parentSHAs: ["main-parent"]))
    }

    private func givenBaseline(_ resolution: TestImpactBaselineResolution) {
        given(resolveBaselineService).resolveTestImpactBaseline(
            fullHandle: .any, serverURL: .any, commitSHA: .any, parentSHAs: .any, ancestorSHAs: .any,
            platform: .any, scheme: .any, testPlan: .any, destination: .any
        ).willReturn(resolution)
    }
}
