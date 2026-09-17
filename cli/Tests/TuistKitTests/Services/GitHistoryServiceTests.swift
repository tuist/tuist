import Foundation
import Mockable
import Path
import Testing
import TuistEnvironment
import TuistGit
import TuistServer
import TuistTesting
@testable import TuistKit

struct GitHistoryServiceTests {
    private let gitController = MockGitControlling()
    private let settingsService = MockGetGitHistorySettingsServicing()
    private let missingCommitsService = MockFindMissingCommitsServicing()
    private let uploadCommitsService = MockUploadCommitsServicing()
    private let subject: GitHistoryService
    private let workingDirectory = try! AbsolutePath(validating: "/repo")
    private let gitInfo = GitInfo(
        ref: "refs/heads/feature",
        branch: "feature",
        sha: "head",
        remoteURLOrigin: nil,
        baseBranch: "main"
    )

    init() {
        subject = GitHistoryService(
            gitController: gitController,
            settingsService: settingsService,
            missingCommitsService: missingCommitsService,
            uploadCommitsService: uploadCommitsService
        )
        given(gitController).isInGitRepository(workingDirectory: .any).willReturn(true)
        given(gitController)
            .gitHistory(workingDirectory: .any, headSHA: .any, baseBranch: .any, limits: .any)
            .willReturn(
                GitHistory(
                    objectFormat: "sha1",
                    headSHA: "head",
                    baseBranch: "main",
                    mergeBaseSHA: "base",
                    commits: [],
                    changedFiles: [],
                    fallbackReason: nil
                )
            )
    }

    @Test(.withMockedEnvironment())
    func collectsTheTrackedFilesTheServerAsksFor() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        given(settingsService)
            .getGitHistorySettings(fullHandle: .any, serverURL: .any)
            .willReturn(
                GitHistorySettings(
                    windowDays: 30,
                    windowCommits: 100,
                    deepenBudgetSeconds: 10,
                    uploadBatchSize: 50,
                    trackedFileGlobs: ["Package.resolved"],
                    trackedFileLimit: 7
                )
            )
        given(gitController)
            .trackedFiles(workingDirectory: .value(workingDirectory), globs: .value(["Package.resolved"]), limit: .value(7))
            .willReturn(GitTrackedFiles(files: [GitTrackedFile(path: "Package.resolved", blobId: "aaa")], truncated: true))

        let collected = try #require(
            await subject.collect(
                gitInfo: gitInfo,
                workingDirectory: workingDirectory,
                fullHandle: "tuist/tuist",
                serverURL: URL(string: "https://tuist.dev")!
            )
        )

        #expect(collected.payload.trackedFiles == [.init(path: "Package.resolved", blobId: "aaa")])
        #expect(collected.payload.trackedFilesTruncated)
        #expect(collected.payload.fallbackReason == nil)
    }

    @Test(.withMockedEnvironment())
    func theEnvironmentOverridesTheGlobsAndAFailureOnlyLeavesAReason() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        Environment.mocked?.variables["TUIST_TRACKED_FILE_GLOBS"] = "Fixtures/**, Snapshots/**"
        given(settingsService)
            .getGitHistorySettings(fullHandle: .any, serverURL: .any)
            .willReturn(GitHistorySettings(
                windowDays: 30,
                windowCommits: 100,
                deepenBudgetSeconds: 10,
                uploadBatchSize: 50,
                trackedFileGlobs: ["Package.resolved"]
            ))
        given(gitController)
            .trackedFiles(workingDirectory: .any, globs: .value(["Fixtures/**", "Snapshots/**"]), limit: .value(5000))
            .willThrow(TestError("git is gone"))

        let collected = try #require(
            await subject.collect(
                gitInfo: gitInfo,
                workingDirectory: workingDirectory,
                fullHandle: "tuist/tuist",
                serverURL: URL(string: "https://tuist.dev")!
            )
        )

        #expect(collected.payload.trackedFiles.isEmpty)
        #expect(collected.payload.source == "client")
        #expect(collected.payload.fallbackReason?.hasPrefix("the tracked files could not be listed: ") == true)
    }
}
