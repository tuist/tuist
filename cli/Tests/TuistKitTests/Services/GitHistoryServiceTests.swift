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
            uploadListingService: uploadListingService,
            cache: GitHistoryCache()
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
                    fallbackReason: nil
                )
            )
        stubConnectedHistory(gitController)
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

    /// A checkout whose history already reaches what the server has.
    private func stubConnectedHistory(_ gitController: MockGitControlling) {
        given(gitController)
            .connectedGitHistory(.any, workingDirectory: .any, refs: .any, limits: .any, unknown: .any)
            .willProduce { history, _, _, _, _ in history }
    }

    @Test(.withMockedEnvironment())
    func connectsTheHistoryToWhatTheServerHasBeforeUploadingIt() async throws {
        // The checkout stopped at `base`, whose parent the server lacks: the deepened history
        // brings it, and it is uploaded with the commits above it.
        given(missingCommitsService)
            .findMissingCommits(fullHandle: .any, serverURL: .any, repositoryURL: .any, shas: .value(["parent"]))
            .willReturn(["parent"])
        given(missingCommitsService)
            .findMissingCommits(fullHandle: .any, serverURL: .any, repositoryURL: .any, shas: .value(["parent", "base", "head"]))
            .willReturn(["parent", "head"])
        given(uploadCommitsService)
            .uploadCommits(
                fullHandle: .any, serverURL: .any, repositoryURL: .any, objectFormat: .any, commits: .any, branchHeads: .any
            )
            .willReturn(())
        gitController.reset()
        given(gitController).isInGitRepository(workingDirectory: .any).willReturn(true)
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
        let collected = GitHistory(
            objectFormat: "sha1",
            headSHA: "head",
            baseBranch: "main",
            mergeBaseSHA: "base",
            commits: [
                GitHistoryCommit(sha: "base", parents: ["parent"], committedAt: Date(timeIntervalSince1970: 2)),
                GitHistoryCommit(sha: "head", parents: ["base"], committedAt: Date(timeIntervalSince1970: 3)),
            ],
            fallbackReason: nil
        )
        given(gitController)
            .gitHistory(workingDirectory: .any, headSHA: .any, baseBranch: .any, limits: .any)
            .willReturn(collected)
        let parent = GitHistoryCommit(sha: "parent", parents: [], committedAt: Date(timeIntervalSince1970: 1))
        nonisolated(unsafe) var unknown: (([String]) async -> [String])?
        given(gitController)
            .connectedGitHistory(.any, workingDirectory: .any, refs: .value(["main"]), limits: .any, unknown: .any)
            .willProduce { history, _, _, _, ask in
                unknown = ask
                return GitHistory(
                    objectFormat: history.objectFormat,
                    headSHA: history.headSHA,
                    baseBranch: history.baseBranch,
                    mergeBaseSHA: history.mergeBaseSHA,
                    commits: [parent] + history.commits,
                    fallbackReason: history.fallbackReason
                )
            }

        _ = await subject.publish(
            gitInfo: gitInfo,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: true
        )

        verify(uploadCommitsService).uploadCommits(
            fullHandle: .any,
            serverURL: .any,
            repositoryURL: .any,
            objectFormat: .any,
            commits: .value([
                GitHistoryCommitPayload(sha: "parent", parents: [], committedAt: Date(timeIntervalSince1970: 1)),
                GitHistoryCommitPayload(sha: "head", parents: ["base"], committedAt: Date(timeIntervalSince1970: 3)),
            ]),
            branchHeads: .any
        ).called(1)
        // What the checkout is deepened by is what the server says it lacks.
        #expect(await unknown?(["parent"]) == ["parent"])
    }

    @Test(.withMockedEnvironment())
    func connectsAPushThroughItsOwnBranchAndTakesAServerThatCannotBeAskedAsHavingTheCommits() async throws {
        given(missingCommitsService)
            .findMissingCommits(fullHandle: .any, serverURL: .any, repositoryURL: .any, shas: .any)
            .willThrow(TestError("the server predates the commit graph"))
        gitController.reset()
        given(gitController).isInGitRepository(workingDirectory: .any).willReturn(true)
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
        given(gitController)
            .gitHistory(workingDirectory: .any, headSHA: .any, baseBranch: .any, limits: .any)
            .willReturn(
                GitHistory(
                    objectFormat: "sha1",
                    headSHA: "head",
                    baseBranch: nil,
                    mergeBaseSHA: nil,
                    commits: [GitHistoryCommit(sha: "head", parents: ["parent"], committedAt: Date(timeIntervalSince1970: 2))],
                    fallbackReason: nil
                )
            )
        nonisolated(unsafe) var unknown: (([String]) async -> [String])?
        given(gitController)
            .connectedGitHistory(.any, workingDirectory: .any, refs: .value(["feature"]), limits: .any, unknown: .any)
            .willProduce { history, _, _, _, ask in
                unknown = ask
                return history
            }

        let collected = await subject.collect(
            gitInfo: GitInfo(
                ref: "refs/heads/feature",
                branch: "feature",
                sha: "head",
                remoteURLOrigin: "git@github.com:acme/app.git",
                baseBranch: nil
            ),
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: true
        )

        #expect(collected?.history.commits.map(\.sha) == ["head"])
        #expect(await unknown?(["parent"]) == [])
    }

    @Test(.withMockedEnvironment())
    func collectsTheHistoryWithTheRemoteAndWhetherTheCheckoutIsDirty() async throws {
        // A dirty checkout is collected in full but its listing is never uploaded.
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
                serverURL: serverURL,
                coverage: true
            )
        )

        #expect(collected.payload.source == "client")
        #expect(collected.payload.dirty)
        #expect(collected.payload.mergeBaseSHA == "base")
        #expect(collected.repositoryURL == "git@github.com:acme/app.git")
        #expect(collected.settings.commitFileLimit == 3)

        await subject.upload(
            collected,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: true
        )
        // The branch head goes up with when the checkout was read, so a late upload cannot move
        // the branch back on the server.
        verify(uploadCommitsService).uploadCommits(
            fullHandle: .any,
            serverURL: .any,
            repositoryURL: .any,
            objectFormat: .any,
            commits: .any,
            branchHeads: .value([
                GitHistoryBranchHead(branch: "feature", sha: "head", observedAt: collected.observedAt),
            ])
        ).called(1)
        verify(missingListingsService).findMissingCommitListings(
            fullHandle: .any,
            serverURL: .any,
            repositoryURL: .any,
            shas: .any
        ).called(0)
        verify(gitController).commitFiles(workingDirectory: .any, sha: .any, limit: .any).called(0)
    }

    @Test(.withMockedEnvironment())
    func collectsOnCIWithoutCoverageButNeverUploadsAListing() async throws {
        Environment.mocked?.variables["CI"] = "1"
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
        given(missingCommitsService)
            .findMissingCommits(fullHandle: .any, serverURL: .any, repositoryURL: .any, shas: .any)
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

        let collected = await subject.collect(
            gitInfo: gitInfo,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: false
        )
        await subject.upload(
            collected,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: false
        )

        #expect(collected != nil)
        verify(uploadCommitsService)
            .uploadCommits(
                fullHandle: .any,
                serverURL: .any,
                repositoryURL: .any,
                objectFormat: .any,
                commits: .any,
                branchHeads: .any
            )
            .called(1)
        verify(missingListingsService).findMissingCommitListings(
            fullHandle: .any,
            serverURL: .any,
            repositoryURL: .any,
            shas: .any
        ).called(0)
    }

    @Test(.withMockedEnvironment())
    func publishesOnceAndTheReportReusesTheCollection() async throws {
        // The stress gate publishes before its plan; the run's report then reads the same checkout.
        Environment.mocked?.variables["CI"] = "1"
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
        given(missingCommitsService)
            .findMissingCommits(fullHandle: .any, serverURL: .any, repositoryURL: .any, shas: .any)
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
            .findMissingCommitListings(fullHandle: .any, serverURL: .any, repositoryURL: .any, shas: .any)
            .willReturn([])

        let published = await subject.publish(
            gitInfo: gitInfo,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: true
        )
        let collected = await subject.collect(
            gitInfo: gitInfo,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: true
        )
        await subject.upload(
            collected,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: true
        )

        #expect(published != nil)
        #expect(collected == published)
        verify(gitController).gitHistory(workingDirectory: .any, headSHA: .any, baseBranch: .any, limits: .any).called(1)
        verify(uploadCommitsService)
            .uploadCommits(
                fullHandle: .any,
                serverURL: .any,
                repositoryURL: .any,
                objectFormat: .any,
                commits: .any,
                branchHeads: .any
            )
            .called(1)
        // The listing still goes up with the report, once the run exists.
        verify(missingListingsService).findMissingCommitListings(
            fullHandle: .any,
            serverURL: .any,
            repositoryURL: .any,
            shas: .any
        ).called(1)
    }

    @Test(.withMockedEnvironment())
    func retriesCommitsTheEarlyPublishCouldNotUpload() async throws {
        Environment.mocked?.variables["CI"] = "1"
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
        given(missingCommitsService)
            .findMissingCommits(fullHandle: .any, serverURL: .any, repositoryURL: .any, shas: .any)
            .willThrow(TestError("unavailable"))
            .findMissingCommits(fullHandle: .any, serverURL: .any, repositoryURL: .any, shas: .any)
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

        let published = await subject.publish(
            gitInfo: gitInfo,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: false
        )
        await subject.upload(
            published,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: false
        )

        verify(uploadCommitsService)
            .uploadCommits(
                fullHandle: .any,
                serverURL: .any,
                repositoryURL: .any,
                objectFormat: .any,
                commits: .any,
                branchHeads: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func collectsNothingOutsideCIWithoutCoverage() async throws {
        let collected = await subject.collect(
            gitInfo: gitInfo,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: false
        )

        #expect(collected == nil)
        verify(gitController).gitHistory(workingDirectory: .any, headSHA: .any, baseBranch: .any, limits: .any).called(0)
    }

    @Test(.withMockedEnvironment())
    func collectsNothingWhenTheUploadIsDisabled() async throws {
        Environment.mocked?.variables["CI"] = "1"
        Environment.mocked?.variables["TUIST_GIT_UPLOAD_ENABLED"] = "false"

        let collected = await subject.collect(
            gitInfo: gitInfo,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: true
        )

        #expect(collected == nil)
        verify(gitController).gitHistory(workingDirectory: .any, headSHA: .any, baseBranch: .any, limits: .any).called(0)
    }

    @Test(.withMockedEnvironment())
    func readsTheCheckoutWithoutFetchingWhenUnshallowingIsDisabled() async throws {
        Environment.mocked?.variables["CI"] = "1"
        Environment.mocked?.variables["TUIST_GIT_UNSHALLOW_ENABLED"] = "false"
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)

        _ = await subject.collect(
            gitInfo: gitInfo,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: false
        )

        verify(gitController)
            .gitHistory(
                workingDirectory: .any,
                headSHA: .any,
                baseBranch: .any,
                limits: .value(GitHistoryLimits(windowDays: 30, windowCommits: 100, deepenBudgetSeconds: 10, remoteAccess: .none))
            )
            .called(1)
    }

    @Test(.withMockedEnvironment(), arguments: [
        (false, GitHistoryRemoteAccess.baseHead),
        (true, GitHistoryRemoteAccess.history),
    ])
    func fetchesHistoryOnlyForCoverage(coverage: Bool, remoteAccess: GitHistoryRemoteAccess) async throws {
        Environment.mocked?.variables["CI"] = "1"
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)

        _ = await subject.collect(
            gitInfo: gitInfo,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: coverage
        )

        verify(gitController)
            .gitHistory(
                workingDirectory: .any,
                headSHA: .any,
                baseBranch: .any,
                limits: .value(GitHistoryLimits(
                    windowDays: 30,
                    windowCommits: 100,
                    deepenBudgetSeconds: 10,
                    remoteAccess: remoteAccess
                ))
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func reportsTheBaseBranchHeadTheRemoteGaveWithoutTheCheckoutHavingIt() async throws {
        // The merge queue's run that tested the commit sent it; this checkout only knows its SHA.
        Environment.mocked?.variables["CI"] = "1"
        let gitController = MockGitControlling()
        stubConnectedHistory(gitController)
        given(gitController).isInGitRepository(workingDirectory: .any).willReturn(true)
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
        given(gitController)
            .gitHistory(workingDirectory: .any, headSHA: .any, baseBranch: .any, limits: .any)
            .willReturn(
                GitHistory(
                    objectFormat: "sha1",
                    headSHA: "head",
                    baseBranch: "main",
                    mergeBaseSHA: nil,
                    baseHeadSHA: "mainhead",
                    commits: [GitHistoryCommit(sha: "head", parents: ["base"], committedAt: Date(timeIntervalSince1970: 2))],
                    fallbackReason: "the base branch main is not in the checkout"
                )
            )
        let subject = GitHistoryService(
            gitController: gitController,
            settingsService: settingsService,
            missingCommitsService: missingCommitsService,
            uploadCommitsService: uploadCommitsService,
            missingListingsService: missingListingsService,
            uploadListingService: uploadListingService,
            cache: GitHistoryCache()
        )
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
            await subject.publish(
                gitInfo: gitInfo,
                workingDirectory: workingDirectory,
                fullHandle: "tuist/tuist",
                serverURL: serverURL,
                coverage: false
            )
        )

        verify(uploadCommitsService).uploadCommits(
            fullHandle: .any,
            serverURL: .any,
            repositoryURL: .any,
            objectFormat: .any,
            commits: .value([]),
            branchHeads: .value([
                GitHistoryBranchHead(branch: "feature", sha: "head", observedAt: collected.observedAt),
                GitHistoryBranchHead(branch: "main", sha: "mainhead", observedAt: collected.observedAt),
            ])
        ).called(1)
    }

    @Test(.withMockedEnvironment())
    func reportsTheBaseBranchHeadTheCheckoutSaw() async throws {
        Environment.mocked?.variables["CI"] = "1"
        let gitController = MockGitControlling()
        stubConnectedHistory(gitController)
        given(gitController).isInGitRepository(workingDirectory: .any).willReturn(true)
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
        given(gitController)
            .gitHistory(workingDirectory: .any, headSHA: .any, baseBranch: .any, limits: .any)
            .willReturn(
                GitHistory(
                    objectFormat: "sha1",
                    headSHA: "head",
                    baseBranch: "main",
                    mergeBaseSHA: "base",
                    baseHeadSHA: "mainhead",
                    commits: [
                        GitHistoryCommit(sha: "mainhead", parents: ["base"], committedAt: Date(timeIntervalSince1970: 3)),
                        GitHistoryCommit(sha: "head", parents: ["base"], committedAt: Date(timeIntervalSince1970: 2)),
                        GitHistoryCommit(sha: "base", parents: [], committedAt: Date(timeIntervalSince1970: 1)),
                    ],
                    fallbackReason: nil
                )
            )
        let subject = GitHistoryService(
            gitController: gitController,
            settingsService: settingsService,
            missingCommitsService: missingCommitsService,
            uploadCommitsService: uploadCommitsService,
            missingListingsService: missingListingsService,
            uploadListingService: uploadListingService,
            cache: GitHistoryCache()
        )
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
                serverURL: serverURL,
                coverage: false
            )
        )
        await subject.upload(
            collected,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: false
        )

        verify(uploadCommitsService).uploadCommits(
            fullHandle: .any,
            serverURL: .any,
            repositoryURL: .any,
            objectFormat: .any,
            commits: .any,
            branchHeads: .value([
                GitHistoryBranchHead(branch: "feature", sha: "head", observedAt: collected.observedAt),
                GitHistoryBranchHead(branch: "main", sha: "mainhead", observedAt: collected.observedAt),
            ])
        ).called(1)
    }

    @Test(.withMockedEnvironment())
    func uploadsTheMissingCommitsAndTheListingOfACleanCheckoutOnce() async throws {
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
            serverURL: serverURL,
            coverage: true
        )
        await subject.upload(
            collected,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: true
        )

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
            serverURL: serverURL,
            coverage: true
        )
        await subject.upload(
            collected,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: true
        )

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
    func neverMovesTheBranchToAHeadTheHistoryDoesNotList() async throws {
        // A re-run of a commit older than the window lists nothing; the server would take an
        // unknown head as the branch's new one.
        let gitController = MockGitControlling()
        stubConnectedHistory(gitController)
        given(gitController).isInGitRepository(workingDirectory: .any).willReturn(true)
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
        given(gitController)
            .gitHistory(workingDirectory: .any, headSHA: .any, baseBranch: .any, limits: .any)
            .willReturn(
                GitHistory(
                    objectFormat: "sha1",
                    headSHA: "old",
                    baseBranch: nil,
                    mergeBaseSHA: nil,
                    commits: [],
                    fallbackReason: "no base branch is known"
                )
            )
        let subject = GitHistoryService(
            gitController: gitController,
            settingsService: settingsService,
            missingCommitsService: missingCommitsService,
            uploadCommitsService: uploadCommitsService,
            missingListingsService: missingListingsService,
            uploadListingService: uploadListingService,
            cache: GitHistoryCache()
        )
        given(missingListingsService)
            .findMissingCommitListings(fullHandle: .any, serverURL: .any, repositoryURL: .any, shas: .any)
            .willReturn([])
        let rerun = GitInfo(ref: "refs/heads/main", branch: "main", sha: "old", remoteURLOrigin: "git@github.com:acme/app.git")

        let collected = await subject.collect(
            gitInfo: rerun,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: true
        )
        await subject.upload(
            collected,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: true
        )

        verify(uploadCommitsService)
            .uploadCommits(
                fullHandle: .any,
                serverURL: .any,
                repositoryURL: .any,
                objectFormat: .any,
                commits: .any,
                branchHeads: .any
            )
            .called(0)
    }

    @Test(.withMockedEnvironment())
    func uploadsNothingWithoutARemote() async throws {
        given(gitController).hasUncommittedChanges(workingDirectory: .any).willReturn(false)
        let local = GitInfo(ref: "refs/heads/feature", branch: "feature", sha: "head", remoteURLOrigin: nil, baseBranch: "main")

        let collected = await subject.collect(
            gitInfo: local,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: true
        )
        await subject.upload(
            collected,
            workingDirectory: workingDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            coverage: true
        )

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
        let noRepository = MockGitControlling()
        given(noRepository).isInGitRepository(workingDirectory: .any).willReturn(false)
        let subject = GitHistoryService(
            gitController: noRepository,
            settingsService: settingsService,
            missingCommitsService: missingCommitsService,
            uploadCommitsService: uploadCommitsService,
            missingListingsService: missingListingsService,
            uploadListingService: uploadListingService,
            cache: GitHistoryCache()
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
                serverURL: serverURL,
                coverage: true
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
