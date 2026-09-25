import Foundation
import Mockable
import Path
import TuistAlert
import TuistEnvironment
import TuistGit
import TuistLogging
import TuistServer
import TuistSupport

/// A run's Git history as collected from the checkout: the payload sent with the run, the
/// commits to upload to the server's graph, the remote that names the repository, and the
/// settings that bounded both.
public struct CollectedGitHistory: Equatable {
    public let payload: TestRunGitHistory
    public let history: GitHistory
    public let branch: String?
    /// The remote the repository is known by on the server; nil when the checkout has none.
    public let repositoryURL: String?
    public let settings: GitHistorySettings
}

/// Collects a run's Git history from the checkout, within the limits the server sets, and uploads
/// what the server's graph lacks once the run exists: the commits, and the commit's file listing
/// when the checkout is clean. Both are best effort: a run is never lost to a history problem,
/// and whatever could not be collected is reported with the run so the server can complete it
/// from the VCS provider.
@Mockable
public protocol GitHistoryServicing {
    func collect(
        gitInfo: GitInfo,
        workingDirectory: AbsolutePath,
        fullHandle: String,
        serverURL: URL
    ) async -> CollectedGitHistory?

    func upload(_ collected: CollectedGitHistory?, workingDirectory: AbsolutePath, fullHandle: String, serverURL: URL) async
}

public struct GitHistoryService: GitHistoryServicing {
    private let gitController: GitControlling
    private let settingsService: GetGitHistorySettingsServicing
    private let missingCommitsService: FindMissingCommitsServicing
    private let uploadCommitsService: UploadCommitsServicing
    private let missingListingsService: FindMissingCommitListingsServicing
    private let uploadListingService: UploadCommitListingServicing

    public init(
        gitController: GitControlling = GitController(),
        settingsService: GetGitHistorySettingsServicing = GetGitHistorySettingsService(),
        missingCommitsService: FindMissingCommitsServicing = FindMissingCommitsService(),
        uploadCommitsService: UploadCommitsServicing = UploadCommitsService(),
        missingListingsService: FindMissingCommitListingsServicing = FindMissingCommitListingsService(),
        uploadListingService: UploadCommitListingServicing = UploadCommitListingService()
    ) {
        self.gitController = gitController
        self.settingsService = settingsService
        self.missingCommitsService = missingCommitsService
        self.uploadCommitsService = uploadCommitsService
        self.missingListingsService = missingListingsService
        self.uploadListingService = uploadListingService
    }

    /// History rides with coverage, which is in early access behind the `COVERAGE` client flag.
    static var enabled: Bool { ClientFeatureFlags.contains("COVERAGE") }

    static var defaultSettings: GitHistorySettings {
        let defaults = GitHistoryLimits()
        return GitHistorySettings(
            windowDays: defaults.windowDays,
            windowCommits: defaults.windowCommits,
            deepenBudgetSeconds: defaults.deepenBudgetSeconds,
            uploadBatchSize: defaults.uploadBatchSize,
            commitFileLimit: defaults.commitFileLimit
        )
    }

    /// Files per listing upload request.
    static let listingBatchSize = 10000

    public func collect(
        gitInfo: GitInfo,
        workingDirectory: AbsolutePath,
        fullHandle: String,
        serverURL: URL
    ) async -> CollectedGitHistory? {
        guard Self.enabled else { return nil }

        // Without a repository there is nothing to collect, but the run still says so, and keeps
        // the pull request identity CI provided, so the server can complete the history from
        // the VCS provider instead of treating the run as a plain one.
        guard gitInfo.sha != nil, await gitController.isInGitRepository(workingDirectory: workingDirectory) else {
            let reason = gitInfo.sha == nil ? "the run's commit is unknown" : "the working directory is not a Git repository"
            return CollectedGitHistory(
                payload: TestRunGitHistory(
                    baseBranch: gitInfo.baseBranch,
                    mergeBaseSHA: nil,
                    isPullRequest: gitInfo.pullRequestNumber != nil || gitInfo.ref?.hasPrefix("refs/pull/") == true,
                    pullRequestNumber: gitInfo.pullRequestNumber,
                    objectFormat: nil,
                    source: "none",
                    fallbackReason: reason,
                    changedFiles: []
                ),
                history: GitHistory(
                    objectFormat: "sha1",
                    headSHA: gitInfo.sha ?? "",
                    baseBranch: gitInfo.baseBranch,
                    mergeBaseSHA: nil,
                    commits: [],
                    changedFiles: [],
                    fallbackReason: reason
                ),
                branch: gitInfo.branch,
                repositoryURL: gitInfo.remoteURLOrigin,
                settings: Self.defaultSettings
            )
        }

        let settings: GitHistorySettings
        do {
            settings = try await settingsService.getGitHistorySettings(fullHandle: fullHandle, serverURL: serverURL)
        } catch {
            Logger.current.debug("Using the default Git history settings: \(error.localizedDescription)")
            settings = Self.defaultSettings
        }

        // A dirty checkout measured code that is not the commit's; the server keeps the run's
        // coverage out of the commit's, and the listing is never taken from it.
        let dirty = (try? await gitController.hasUncommittedChanges(workingDirectory: workingDirectory)) ?? false

        let history: GitHistory
        do {
            history = try await gitController.gitHistory(
                workingDirectory: workingDirectory,
                headSHA: gitInfo.sha,
                baseBranch: gitInfo.baseBranch,
                limits: GitHistoryLimits(
                    windowDays: settings.windowDays,
                    windowCommits: settings.windowCommits,
                    deepenBudgetSeconds: settings.deepenBudgetSeconds,
                    uploadBatchSize: settings.uploadBatchSize,
                    commitFileLimit: settings.commitFileLimit
                )
            )
        } catch {
            AlertController.current.warning(.alert("The run's Git history could not be read: \(error.localizedDescription)"))
            return CollectedGitHistory(
                payload: TestRunGitHistory(
                    baseBranch: gitInfo.baseBranch,
                    mergeBaseSHA: nil,
                    isPullRequest: gitInfo.pullRequestNumber != nil,
                    pullRequestNumber: gitInfo.pullRequestNumber,
                    objectFormat: nil,
                    source: "none",
                    fallbackReason: error.localizedDescription,
                    changedFiles: [],
                    dirty: dirty
                ),
                history: GitHistory(
                    objectFormat: "sha1",
                    headSHA: gitInfo.sha ?? "",
                    baseBranch: gitInfo.baseBranch,
                    mergeBaseSHA: nil,
                    commits: [],
                    changedFiles: [],
                    fallbackReason: error.localizedDescription
                ),
                branch: gitInfo.branch,
                repositoryURL: gitInfo.remoteURLOrigin,
                settings: settings
            )
        }

        let payload = TestRunGitHistory(
            baseBranch: history.baseBranch,
            mergeBaseSHA: history.mergeBaseSHA,
            isPullRequest: gitInfo.pullRequestNumber != nil || gitInfo.ref?.hasPrefix("refs/pull/") == true,
            pullRequestNumber: gitInfo.pullRequestNumber,
            objectFormat: history.objectFormat,
            source: "client",
            fallbackReason: history.fallbackReason,
            changedFiles: history.changedFiles.map { file in
                TestRunGitHistory.ChangedFile(
                    path: file.path,
                    previousPath: file.previousPath,
                    status: file.status.rawValue,
                    blobId: file.blobId,
                    hunks: file.hunks.map { (start: $0.start, end: $0.end) },
                    truncated: file.truncated
                )
            },
            dirty: dirty
        )

        return CollectedGitHistory(
            payload: payload,
            history: history,
            branch: gitInfo.branch,
            repositoryURL: gitInfo.remoteURLOrigin,
            settings: settings
        )
    }

    /// Sends the commits the server lacks, oldest first so their generation numbers are exact,
    /// in batches of the server's size, the branch head the run was on, and the commit's file
    /// listing when the server lacks it and the checkout is clean. The repository is named by its
    /// remote; a checkout without one has no graph to upload to.
    public func upload(
        _ collected: CollectedGitHistory?,
        workingDirectory: AbsolutePath,
        fullHandle: String,
        serverURL: URL
    ) async {
        guard let collected, let repositoryURL = collected.repositoryURL, !repositoryURL.isEmpty else { return }

        do {
            try await uploadCommits(collected, repositoryURL: repositoryURL, fullHandle: fullHandle, serverURL: serverURL)
        } catch {
            AlertController.current.warning(.alert("The run's Git history could not be uploaded: \(error.localizedDescription)"))
        }

        do {
            try await uploadListing(
                collected,
                repositoryURL: repositoryURL,
                workingDirectory: workingDirectory,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
        } catch {
            AlertController.current
                .warning(.alert("The commit's file listing could not be uploaded: \(error.localizedDescription)"))
        }
    }

    private func uploadCommits(
        _ collected: CollectedGitHistory,
        repositoryURL: String,
        fullHandle: String,
        serverURL: URL
    ) async throws {
        let commits = collected.history.commits
        guard !commits.isEmpty else { return }
        let batchSize = max(collected.settings.uploadBatchSize, 1)

        var missing = Set<String>()
        for start in stride(from: 0, to: commits.count, by: 5000) {
            let batch = commits[start ..< min(start + 5000, commits.count)].map(\.sha)
            missing.formUnion(
                try await missingCommitsService.findMissingCommits(
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    repositoryURL: repositoryURL,
                    shas: batch
                )
            )
        }

        let toUpload = commits
            .filter { missing.contains($0.sha) }
            .sorted { $0.committedAt < $1.committedAt }
            .map { GitHistoryCommitPayload(sha: $0.sha, parents: $0.parents, committedAt: $0.committedAt) }

        let branchHeads: [(branch: String, sha: String)] =
            collected.branch.map { [(branch: $0, sha: collected.history.headSHA)] } ?? []

        if toUpload.isEmpty {
            if !branchHeads.isEmpty {
                try await uploadCommitsService.uploadCommits(
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    repositoryURL: repositoryURL,
                    objectFormat: collected.history.objectFormat,
                    commits: [],
                    branchHeads: branchHeads
                )
            }
            return
        }

        for start in stride(from: 0, to: toUpload.count, by: batchSize) {
            let end = min(start + batchSize, toUpload.count)
            try await uploadCommitsService.uploadCommits(
                fullHandle: fullHandle,
                serverURL: serverURL,
                repositoryURL: repositoryURL,
                objectFormat: collected.history.objectFormat,
                commits: Array(toUpload[start ..< end]),
                branchHeads: end == toUpload.count ? branchHeads : []
            )
        }
    }

    private func uploadListing(
        _ collected: CollectedGitHistory,
        repositoryURL: String,
        workingDirectory: AbsolutePath,
        fullHandle: String,
        serverURL: URL
    ) async throws {
        let sha = collected.history.headSHA
        guard !sha.isEmpty, collected.payload.source == "client", !collected.payload.dirty else { return }

        let missing = try await missingListingsService.findMissingCommitListings(
            fullHandle: fullHandle,
            serverURL: serverURL,
            repositoryURL: repositoryURL,
            shas: [sha]
        )
        guard missing.contains(sha) else { return }

        let listing = try await gitController.commitFiles(
            workingDirectory: workingDirectory,
            sha: sha,
            limit: collected.settings.commitFileLimit
        )
        let files = listing.files.map { GitCommitFilePayload(path: $0.path, blobId: $0.blobId, mode: $0.mode) }
        let batches = stride(from: 0, to: max(files.count, 1), by: Self.listingBatchSize).map { start in
            Array(files[start ..< min(start + Self.listingBatchSize, files.count)])
        }

        for (index, batch) in batches.enumerated() {
            try await uploadListingService.uploadCommitListing(
                fullHandle: fullHandle,
                serverURL: serverURL,
                repositoryURL: repositoryURL,
                sha: sha,
                files: batch,
                complete: index == batches.count - 1,
                truncated: listing.truncated,
                filesCount: files.count
            )
        }
    }
}
