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
    private let missingListingsService = MockFindMissingCommitListingsServicing()
    private let uploadListingService = MockUploadCommitListingServicing()
    private let subject: GitHistoryService
    private let workingDirectory = try! AbsolutePath(validating: "/repo")
    private let serverURL = URL(string: "https://tuist.dev")!
    private let gitInfo = GitInfo(
        ref: "refs/heads/feature",
        branch: "feature",
        sha: "head",
        remoteURLOrigin: "git@github.com:acme/app.git",
        baseBranch: "main"
    )

    init() {
        subject = GitHistoryService(
            gitController: gitController,
            settingsService: settingsService,
            missingCommitsService: missingCommitsService,
            uploadCommitsService: uploadCommitsService,
            missingListingsService: missingListingsService,
            uploadListingService: uploadListingService
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
                    commits: [
                        GitHistoryCommit(sha: "base", parents: [], committedAt: Date(timeIntervalSince1970: 1)),
                        GitHistoryCommit(sha: "head", parents: ["base"], committedAt: Date(timeIntervalSince1970: 2)),
                    ],
                    changedFiles: [],
                    fallbackReason: nil
                )
            )
        given(settingsService)
            .getGitHistorySettings(fullHandle: .any, serverURL: .any)
            .willReturn(GitHistorySettings(
                windowDays: 30,
                windowCommits: 100,
                deepenBudgetSeconds: 10,
                uploadBatchSize: 50,
                commitFileLimit: 3
            ))
    }

    @Test(.withMockedEnvironment())
    func collectsTheHistoryWithTheRemoteAndWhetherTheCheckoutIsDirty() async throws {
        // A dirty checkout is collected in full but its listing is never uploaded.
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        given(gitController).hasUncommittedChanges(workingDirectory: .value(workingDirectory)).willReturn(true)
        given(missingCommitsService)
            .findMissingCommits(fullHandle: .any, serverURL: .any, repositoryURL: .any, shas: .any)
            .willReturn([])
        given(uploadCommitsService)
            .uploadCommits(
                fullHandle: .any,
                serverURL: .any,
                repositoryURL: .any,
                objectFormat: .any,
                commits: .any,
                branchHeads: .any
            )
            .willReturn(())

        let collected = try #require(
            await subject.collect(
                gitInfo: gitInfo,
                workingDirectory: workingDirectory,
                fullHandle: "tuist/tuist",
                serverURL: serverURL
            )
        )

        #expect(collected.payload.source == "client")
        #expect(collected.payload.dirty)
        #expect(collected.payload.mergeBaseSHA == "base")
        #expect(collected.repositoryURL == "git@github.com:acme/app.git")
        #expect(collected.settings.commitFileLimit == 3)

        await subject.upload(collected, workingDirectory: workingDirectory, fullHandle: "tuist/tuist", serverURL: serverURL)
        verify(missingListingsService).findMissingCommitListings(
            fullHandle: .any,
            serverURL: .any,
            repositoryURL: .any,
            shas: .any
        ).called(0)
        verify(gitController).commitFiles(workingDirectory: .any, sha: .any, limit: .any).called(0)
    }

    @Test(.withMockedEnvironment())
    func uploadsTheMissingCommitsAndTheListingOfACleanCheckoutOnce() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
        given(missingCommitsService)
            .findMissingCommits(
                fullHandle: .any,
                serverURL: .any,
                repositoryURL: .value("git@github.com:acme/app.git"),
                shas: .any
            )
            .willReturn(["head"])
        given(uploadCommitsService)
            .uploadCommits(
                fullHandle: .any,
                serverURL: .any,
                repositoryURL: .any,
                objectFormat: .any,
                commits: .any,
                branchHeads: .any
            )
            .willReturn(())
        given(missingListingsService)
            .findMissingCommitListings(fullHandle: .any, serverURL: .any, repositoryURL: .any, shas: .value(["head"]))
            .willReturn(["head"])
        given(gitController)
            .commitFiles(workingDirectory: .value(workingDirectory), sha: .value("head"), limit: .value(3))
            .willReturn(GitCommitFiles(
                files: [
                    GitCommitFile(path: "Package.resolved", blobId: "aaa", mode: 0o100644),
                    GitCommitFile(path: "Sources/A.swift", blobId: "bbb", mode: 0o100644),
                ],
                truncated: true
            ))
        given(uploadListingService)
            .uploadCommitListing(
                fullHandle: .any,
                serverURL: .any,
                repositoryURL: .value("git@github.com:acme/app.git"),
                sha: .value("head"),
                files: .value([
                    GitCommitFilePayload(path: "Package.resolved", blobId: "aaa", mode: 0o100644),
                    GitCommitFilePayload(path: "Sources/A.swift", blobId: "bbb", mode: 0o100644),
                ]),
                complete: .value(true),
                truncated: .value(true),
                filesCount: .value(2)
            )
            .willReturn(())

        let collected = await subject.collect(
            gitInfo: gitInfo,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL
        )
        await subject.upload(collected, workingDirectory: workingDirectory, fullHandle: "tuist/tuist", serverURL: serverURL)

        verify(uploadCommitsService)
            .uploadCommits(
                fullHandle: .any,
                serverURL: .any,
                repositoryURL: .value("git@github.com:acme/app.git"),
                objectFormat: .value("sha1"),
                commits: .value([GitHistoryCommitPayload(
                    sha: "head",
                    parents: ["base"],
                    committedAt: Date(timeIntervalSince1970: 2)
                )]),
                branchHeads: .any
            )
            .called(1)
        verify(uploadListingService)
            .uploadCommitListing(
                fullHandle: .any,
                serverURL: .any,
                repositoryURL: .any,
                sha: .any,
                files: .any,
                complete: .any,
                truncated: .any,
                filesCount: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func neverUploadsAListingTheServerHas() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
        given(missingCommitsService)
            .findMissingCommits(fullHandle: .any, serverURL: .any, repositoryURL: .any, shas: .any)
            .willReturn([])
        given(uploadCommitsService)
            .uploadCommits(
                fullHandle: .any,
                serverURL: .any,
                repositoryURL: .any,
                objectFormat: .any,
                commits: .any,
                branchHeads: .any
            )
            .willReturn(())
        given(missingListingsService)
            .findMissingCommitListings(fullHandle: .any, serverURL: .any, repositoryURL: .any, shas: .any)
            .willReturn([])

        let collected = await subject.collect(
            gitInfo: gitInfo,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL
        )
        await subject.upload(collected, workingDirectory: workingDirectory, fullHandle: "tuist/tuist", serverURL: serverURL)

        verify(gitController).commitFiles(workingDirectory: .any, sha: .any, limit: .any).called(0)
        verify(uploadListingService)
            .uploadCommitListing(
                fullHandle: .any,
                serverURL: .any,
                repositoryURL: .any,
                sha: .any,
                files: .any,
                complete: .any,
                truncated: .any,
                filesCount: .any
            )
            .called(0)
        // The branch head still reaches the server when nothing is new.
        verify(uploadCommitsService)
            .uploadCommits(
                fullHandle: .any,
                serverURL: .any,
                repositoryURL: .any,
                objectFormat: .any,
                commits: .value([]),
                branchHeads: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func uploadsNothingWithoutARemote() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
        let local = GitInfo(ref: "refs/heads/feature", branch: "feature", sha: "head", remoteURLOrigin: nil, baseBranch: "main")

        let collected = await subject.collect(
            gitInfo: local,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL
        )
        await subject.upload(collected, workingDirectory: workingDirectory, fullHandle: "tuist/tuist", serverURL: serverURL)

        #expect(collected?.repositoryURL == nil)
        verify(missingCommitsService).findMissingCommits(fullHandle: .any, serverURL: .any, repositoryURL: .any, shas: .any)
            .called(0)
        verify(missingListingsService).findMissingCommitListings(
            fullHandle: .any,
            serverURL: .any,
            repositoryURL: .any,
            shas: .any
        ).called(0)
    }

    @Test(.withMockedEnvironment())
    func reportsARunWithoutARepositoryAsHistorylessButKeepsItsPullRequest() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        let noRepository = MockGitControlling()
        given(noRepository).isInGitRepository(workingDirectory: .any).willReturn(false)
        let subject = GitHistoryService(
            gitController: noRepository,
            settingsService: settingsService,
            missingCommitsService: missingCommitsService,
            uploadCommitsService: uploadCommitsService,
            missingListingsService: missingListingsService,
            uploadListingService: uploadListingService
        )
        let gitInfo = GitInfo(
            ref: "refs/pull/7/merge",
            branch: "feature",
            sha: "head",
            remoteURLOrigin: nil,
            baseBranch: "main",
            pullRequestNumber: 7
        )

        let collected = try #require(
            await subject.collect(
                gitInfo: gitInfo,
                workingDirectory: workingDirectory,
                fullHandle: "tuist/tuist",
                serverURL: serverURL
            )
        )

        #expect(collected.payload.source == "none")
        #expect(collected.payload.fallbackReason == "the working directory is not a Git repository")
        #expect(collected.payload.isPullRequest)
        #expect(collected.payload.pullRequestNumber == 7)
        #expect(collected.payload.baseBranch == "main")
        #expect(collected.payload.dirty == false)
        #expect(collected.history.commits.isEmpty)
    }
}
