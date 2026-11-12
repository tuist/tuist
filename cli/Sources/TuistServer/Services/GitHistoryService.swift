#if canImport(TuistGit)
    import Foundation
    import Mockable
    import Path
    import TuistAlert
    import TuistEnvironment
    import TuistGit
    import TuistLogging
    import TuistSupport

    /// A run's Git history as collected from the checkout: the payload sent with the run, the
    /// commits to upload to the server's graph, the remote that names the repository, and the
    /// settings that bounded both.
    public struct CollectedGitHistory: Equatable, Sendable {
        public let payload: TestRunGitHistory
        public let history: GitHistory
        public let branch: String?
        /// The remote the repository is known by on the server; nil when the checkout has none.
        public let repositoryURL: String?
        public let settings: GitHistorySettings
        /// When the checkout's head was read: the server moves the branch only on an observation no
        /// older than the one that last moved it, so a late upload cannot move it back.
        public let observedAt: Date
    }

    /// Collects a run's Git history from the checkout, within the limits the server sets, and uploads
    /// what the server's graph lacks: the commits and branch heads before the server is asked anything
    /// that reads the graph (`publish`), and the commit's file listing once the run exists, when the
    /// checkout is clean. A process collects and publishes a checkout's history once
    /// (`GitHistoryCache`). Both are best effort: a run is never lost to a history problem, and
    /// whatever could not be collected is reported with the run so the server can complete it from
    /// the VCS provider.
    @Mockable
    public protocol GitHistoryServicing {
        /// `coverage` is whether the run uploads coverage (`UploadResultBundleService.uploadsCoverage`).
        func collect(
            gitInfo: GitInfo,
            workingDirectory: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            coverage: Bool
        ) async -> CollectedGitHistory?

        /// Collects the history and uploads its commits and branch heads, once per process.
        func publish(
            gitInfo: GitInfo,
            workingDirectory: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            coverage: Bool
        ) async -> CollectedGitHistory?

        func upload(
            _ collected: CollectedGitHistory?,
            workingDirectory: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            coverage: Bool
        ) async
    }

    public struct GitHistoryService: GitHistoryServicing {
        private let gitController: GitControlling
        private let settingsService: GetGitHistorySettingsServicing
        private let missingCommitsService: FindMissingCommitsServicing
        private let uploadCommitsService: UploadCommitsServicing
        private let missingListingsService: FindMissingCommitListingsServicing
        private let uploadListingService: UploadCommitListingServicing
        private let cache: GitHistoryCache

        public init(
            gitController: GitControlling = GitController(),
            settingsService: GetGitHistorySettingsServicing = GetGitHistorySettingsService(),
            missingCommitsService: FindMissingCommitsServicing = FindMissingCommitsService(),
            uploadCommitsService: UploadCommitsServicing = UploadCommitsService(),
            missingListingsService: FindMissingCommitListingsServicing = FindMissingCommitListingsService(),
            uploadListingService: UploadCommitListingServicing = UploadCommitListingService(),
            cache: GitHistoryCache = .shared
        ) {
            self.gitController = gitController
            self.settingsService = settingsService
            self.missingCommitsService = missingCommitsService
            self.uploadCommitsService = uploadCommitsService
            self.missingListingsService = missingListingsService
            self.uploadListingService = uploadListingService
            self.cache = cache
        }

        /// History is collected on CI, where it places runs on the default branch's history, and locally
        /// with coverage. `TUIST_GIT_UPLOAD_ENABLED=false` turns it off.
        static func enabled(coverage: Bool) -> Bool {
            guard !Environment.current.isVariableFalsy("TUIST_GIT_UPLOAD_ENABLED") else { return false }
            return Environment.current.isCI || coverage
        }

        /// Only coverage needs the merge base, so only coverage fetches history; any other run reads the
        /// checkout and asks the remote for the base branch's latest commit at most.
        /// `TUIST_GIT_UNSHALLOW_ENABLED=false` keeps every run to what the checkout has.
        public static func remoteAccess(coverage: Bool) -> GitHistoryRemoteAccess {
            guard !Environment.current.isVariableFalsy("TUIST_GIT_UNSHALLOW_ENABLED") else { return .none }
            return coverage ? .history : .baseHead
        }

        /// History is best effort, so outside coverage a failure is only logged: a server that predates
        /// it, or a checkout it cannot read, is no reason to flag every run.
        private static func warn(_ message: String, coverage: Bool) {
            if coverage {
                AlertController.current.warning(.alert("\(message)"))
            } else {
                Logger.current.debug("\(message)")
            }
        }

        static var defaultSettings: GitHistorySettings {
            let defaults = GitHistoryLimits()
            return GitHistorySettings(
                windowDays: defaults.windowDays,
                windowCommits: defaults.windowCommits,
                deepenBudgetSeconds: defaults.deepenBudgetSeconds,
                uploadBatchSize: 500,
                commitFileLimit: 50000
            )
        }

        /// Files per listing upload request.
        static let listingBatchSize = 10000

        public func collect(
            gitInfo: GitInfo,
            workingDirectory: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            coverage: Bool
        ) async -> CollectedGitHistory? {
            guard Self.enabled(coverage: coverage) else { return nil }
            let key = GitHistoryCache.key(
                workingDirectory: workingDirectory,
                sha: gitInfo.sha,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            if let collected = await cache.collected(key) { return collected }
            let collected = await collectFromCheckout(
                gitInfo: gitInfo,
                workingDirectory: workingDirectory,
                fullHandle: fullHandle,
                serverURL: serverURL,
                coverage: coverage
            )
            await cache.store(collected, key: key)
            return collected
        }

        public func publish(
            gitInfo: GitInfo,
            workingDirectory: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            coverage: Bool
        ) async -> CollectedGitHistory? {
            let collected = await collect(
                gitInfo: gitInfo,
                workingDirectory: workingDirectory,
                fullHandle: fullHandle,
                serverURL: serverURL,
                coverage: coverage
            )
            await publishCommits(
                collected,
                workingDirectory: workingDirectory,
                fullHandle: fullHandle,
                serverURL: serverURL,
                coverage: coverage
            )
            return collected
        }

        private func collectFromCheckout(
            gitInfo: GitInfo,
            workingDirectory: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            coverage: Bool
        ) async -> CollectedGitHistory {
            let observedAt = Date()

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
                        fallbackReason: reason
                    ),
                    history: GitHistory(
                        objectFormat: "sha1",
                        headSHA: gitInfo.sha ?? "",
                        baseBranch: gitInfo.baseBranch,
                        mergeBaseSHA: nil,
                        commits: [],
                        fallbackReason: reason
                    ),
                    branch: gitInfo.branch,
                    repositoryURL: gitInfo.remoteURLOrigin,
                    settings: Self.defaultSettings,
                    observedAt: observedAt
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
                history = try await checkoutHistory(
                    gitController: gitController,
                    missingCommitsService: missingCommitsService,
                    gitInfo: gitInfo,
                    workingDirectory: workingDirectory,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    limits: GitHistoryLimits(
                        windowDays: settings.windowDays,
                        windowCommits: settings.windowCommits,
                        deepenBudgetSeconds: settings.deepenBudgetSeconds,
                        remoteAccess: Self.remoteAccess(coverage: coverage)
                    )
                )
            } catch {
                Self.warn("The run's Git history could not be read: \(error.localizedDescription)", coverage: coverage)
                return CollectedGitHistory(
                    payload: TestRunGitHistory(
                        baseBranch: gitInfo.baseBranch,
                        mergeBaseSHA: nil,
                        isPullRequest: gitInfo.pullRequestNumber != nil,
                        pullRequestNumber: gitInfo.pullRequestNumber,
                        objectFormat: nil,
                        source: "none",
                        fallbackReason: error.localizedDescription,
                        dirty: dirty
                    ),
                    history: GitHistory(
                        objectFormat: "sha1",
                        headSHA: gitInfo.sha ?? "",
                        baseBranch: gitInfo.baseBranch,
                        mergeBaseSHA: nil,
                        commits: [],
                        fallbackReason: error.localizedDescription
                    ),
                    branch: gitInfo.branch,
                    repositoryURL: gitInfo.remoteURLOrigin,
                    settings: settings,
                    observedAt: observedAt
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
                dirty: dirty
            )

            return CollectedGitHistory(
                payload: payload,
                history: history,
                branch: gitInfo.branch,
                repositoryURL: gitInfo.remoteURLOrigin,
                settings: settings,
                observedAt: observedAt
            )
        }

        /// Sends the commits the server lacks, oldest first so their generation numbers are exact,
        /// in batches of the server's size, the branch head the run was on and the base branch's as the
        /// checkout saw it, and, with coverage, the commit's file listing when the server lacks it and
        /// the checkout is clean. The repository is named by its remote; a checkout without one has no
        /// graph to upload to.
        public func upload(
            _ collected: CollectedGitHistory?,
            workingDirectory: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            coverage: Bool
        ) async {
            await publishCommits(
                collected,
                workingDirectory: workingDirectory,
                fullHandle: fullHandle,
                serverURL: serverURL,
                coverage: coverage
            )

            guard coverage, let collected, let repositoryURL = collected.repositoryURL, !repositoryURL.isEmpty
            else { return }
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

        /// Uploads the commits and branch heads unless this process already did, and records it only
        /// once they are up, so a failed attempt is retried when the run is reported.
        private func publishCommits(
            _ collected: CollectedGitHistory?,
            workingDirectory: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            coverage: Bool
        ) async {
            guard let collected, let repositoryURL = collected.repositoryURL, !repositoryURL.isEmpty else { return }
            let key = GitHistoryCache.key(
                workingDirectory: workingDirectory,
                sha: collected.history.headSHA,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            guard await !cache.isPublished(key) else { return }
            do {
                try await uploadCommits(collected, repositoryURL: repositoryURL, fullHandle: fullHandle, serverURL: serverURL)
                await cache.markPublished(key)
            } catch {
                Self.warn("The run's Git history could not be uploaded: \(error.localizedDescription)", coverage: coverage)
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

            var branchHeads = collected.branch.map {
                [GitHistoryBranchHead(branch: $0, sha: collected.history.headSHA, observedAt: collected.observedAt)]
            } ?? []
            // A pull request's run is how the default branch's head is seen between the default
            // branch's own runs. The checkout may not have that commit: the run that tested it, a
            // merge queue's typically, sent it already.
            if let baseBranch = collected.history.baseBranch, baseBranch != collected.branch,
               let baseHeadSHA = collected.history.baseHeadSHA
            {
                branchHeads.append(GitHistoryBranchHead(branch: baseBranch, sha: baseHeadSHA, observedAt: collected.observedAt))
            }

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

    /// The checkout's history, with the commits between it and what the server has fetched when a
    /// shallow clone stops short of them: the server places a commit on its branch from the parents it
    /// has, so a commit that arrives before its parent leaves the parent off the branch for good. A
    /// server that cannot be asked counts as having them, and nothing is fetched. Only on CI, where
    /// runs race each other and the clone is thrown away: the fetch makes it a partial clone.
    private func checkoutHistory(
        gitController: GitControlling,
        missingCommitsService: FindMissingCommitsServicing,
        gitInfo: GitInfo,
        workingDirectory: AbsolutePath,
        fullHandle: String,
        serverURL: URL,
        limits: GitHistoryLimits
    ) async throws -> GitHistory {
        let history = try await gitController.gitHistory(
            workingDirectory: workingDirectory,
            headSHA: gitInfo.sha,
            baseBranch: gitInfo.baseBranch,
            limits: limits
        )
        guard Environment.current.isCI, let repositoryURL = gitInfo.remoteURLOrigin, !repositoryURL.isEmpty
        else { return history }
        return await gitController.connectedGitHistory(
            history,
            workingDirectory: workingDirectory,
            // The full ref, so a branch name is never read as a tag or as an option of `git fetch`.
            refs: [gitInfo.baseBranch ?? gitInfo.branch].compactMap { $0 }.map { "refs/heads/\($0)" },
            limits: limits,
            unknown: { shas in
                (try? await missingCommitsService.findMissingCommits(
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    repositoryURL: repositoryURL,
                    shas: shas
                )) ?? []
            }
        )
    }

    /// The history a process collected per checkout and commit, and whether its commits are up, so the
    /// stress gate's early upload and the run's report share one collection and one upload.
    public actor GitHistoryCache {
        public static let shared = GitHistoryCache()

        private var collected: [String: CollectedGitHistory] = [:]
        private var published: Set<String> = []

        public init() {}

        static func key(workingDirectory: AbsolutePath, sha: String?, fullHandle: String, serverURL: URL) -> String {
            [serverURL.absoluteString, fullHandle, workingDirectory.pathString, sha ?? ""].joined(separator: "\n")
        }

        func collected(_ key: String) -> CollectedGitHistory? { collected[key] }

        func store(_ history: CollectedGitHistory, key: String) { collected[key] = history }

        func isPublished(_ key: String) -> Bool { published.contains(key) }

        func markPublished(_ key: String) { published.insert(key) }
    }
#endif
