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
/// commits to upload to the server's graph, and the settings that bounded both.
public struct CollectedGitHistory: Equatable {
    public let payload: TestRunGitHistory
    public let history: GitHistory
    public let branch: String?
    public let settings: GitHistorySettings
}

/// Collects a run's Git history from the checkout, within the limits the server sets, and uploads
/// the commits the server's graph lacks once the run exists. Both are best effort: a run is never
/// lost to a history problem, and whatever could not be collected is reported with the run so the
/// server can complete it from the VCS provider.
@Mockable
public protocol GitHistoryServicing {
    func collect(
        gitInfo: GitInfo,
        workingDirectory: AbsolutePath,
        fullHandle: String,
        serverURL: URL
    ) async -> CollectedGitHistory?

    func upload(_ collected: CollectedGitHistory?, fullHandle: String, serverURL: URL) async
}

public struct GitHistoryService: GitHistoryServicing {
    private let gitController: GitControlling
    private let settingsService: GetGitHistorySettingsServicing
    private let missingCommitsService: FindMissingCommitsServicing
    private let uploadCommitsService: UploadCommitsServicing

    public init(
        gitController: GitControlling = GitController(),
        settingsService: GetGitHistorySettingsServicing = GetGitHistorySettingsService(),
        missingCommitsService: FindMissingCommitsServicing = FindMissingCommitsService(),
        uploadCommitsService: UploadCommitsServicing = UploadCommitsService()
    ) {
        self.gitController = gitController
        self.settingsService = settingsService
        self.missingCommitsService = missingCommitsService
        self.uploadCommitsService = uploadCommitsService
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
            trackedFileGlobs: defaults.trackedFileGlobs,
            trackedFileLimit: defaults.trackedFileLimit
        )
    }

    /// A run may override the project's tracked-file globs with a comma-separated list.
    static let trackedFileGlobsVariable = "TUIST_TRACKED_FILE_GLOBS"

    static func trackedFileGlobs(settings: GitHistorySettings, environment: [String: String]) -> [String] {
        guard let override = environment[trackedFileGlobsVariable] else { return settings.trackedFileGlobs }
        return override.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

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

        let (trackedFiles, trackedFilesReason) = await trackedFiles(workingDirectory: workingDirectory, settings: settings)

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
                    uploadBatchSize: settings.uploadBatchSize
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
                    fallbackReason: [error.localizedDescription, trackedFilesReason].compactMap { $0 }.joined(separator: "; "),
                    changedFiles: [],
                    trackedFiles: trackedFiles.files.map { .init(path: $0.path, blobId: $0.blobId) },
                    trackedFilesTruncated: trackedFiles.truncated
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
            fallbackReason: [history.fallbackReason, trackedFilesReason].compactMap { $0 }.joined(separator: "; ").nilIfEmpty,
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
            trackedFiles: trackedFiles.files.map { .init(path: $0.path, blobId: $0.blobId) },
            trackedFilesTruncated: trackedFiles.truncated
        )

        return CollectedGitHistory(payload: payload, history: history, branch: gitInfo.branch, settings: settings)
    }

    /// The tracked files with their blobs, and a reason when they could not be listed. Best
    /// effort like the rest of the history.
    private func trackedFiles(
        workingDirectory: AbsolutePath,
        settings: GitHistorySettings
    ) async -> (GitTrackedFiles, String?) {
        let globs = Self.trackedFileGlobs(settings: settings, environment: Environment.current.variables)
        do {
            let files = try await gitController.trackedFiles(
                workingDirectory: workingDirectory,
                globs: globs,
                limit: settings.trackedFileLimit
            )
            return (files, nil)
        } catch {
            return (
                GitTrackedFiles(files: [], truncated: false),
                "the tracked files could not be listed: \(error.localizedDescription)"
            )
        }
    }

    /// Sends the commits the server lacks, oldest first so their generation numbers are exact,
    /// in batches of the server's size, and the branch head the run was on.
    public func upload(_ collected: CollectedGitHistory?, fullHandle: String, serverURL: URL) async {
        guard let collected, !collected.history.commits.isEmpty else { return }
        let commits = collected.history.commits
        let batchSize = max(collected.settings.uploadBatchSize, 1)

        do {
            var missing = Set<String>()
            for start in stride(from: 0, to: commits.count, by: 5000) {
                let batch = commits[start ..< min(start + 5000, commits.count)].map(\.sha)
                missing.formUnion(
                    try await missingCommitsService.findMissingCommits(fullHandle: fullHandle, serverURL: serverURL, shas: batch)
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
                    objectFormat: collected.history.objectFormat,
                    commits: Array(toUpload[start ..< end]),
                    branchHeads: end == toUpload.count ? branchHeads : []
                )
            }
        } catch {
            AlertController.current.warning(.alert("The run's Git history could not be uploaded: \(error.localizedDescription)"))
        }
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
