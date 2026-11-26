import Foundation
import Mockable
import Noora
import Path
import TuistAlert
import TuistConfigLoader
import TuistEnvironment
import TuistGit
import TuistServer
import TuistSupport

enum SnapshotsUploadServiceError: Equatable, LocalizedError {
    case missingFullHandle
    case missingCommit(AbsolutePath)
    case missingDirectory(AbsolutePath)
    case changesNeedReview(summary: String, url: String)
    case changesRejected(summary: String, url: String)
    case comparisonFailed(url: String)
    case comparisonTimedOut(url: String)

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "The project's full handle is missing. Pass --full-handle or run it from a Tuist project."
        case let .missingCommit(path):
            return "Snapshots are compared along Git history and reviewed per commit, but \(path.pathString) isn't in a Git repository with a commit."
        case let .missingDirectory(path):
            return "The snapshot directory \(path.pathString) doesn't exist."
        case let .changesNeedReview(summary, url):
            return "Snapshots changed against the baseline (\(summary)). Review them at \(url)"
        case let .changesRejected(summary, url):
            return "A reviewer rejected these snapshot changes (\(summary)). See \(url)"
        case let .comparisonFailed(url):
            return "The snapshot comparison failed. See \(url)"
        case let .comparisonTimedOut(url):
            return "The snapshot comparison didn't finish in time, so these snapshots have no verdict. See \(url)"
        }
    }
}

/// Where `SnapshotsUploadService` uploads a directory of recorded images to.
public struct SnapshotsUploadOptions: Equatable, Sendable {
    public var set: String
    /// The Tuist project's directory, which also locates the Git checkout.
    public var path: AbsolutePath
    public var fullHandle: String?
    /// The share of pixels that may differ before an image counts as changed, for images whose
    /// metadata doesn't set one.
    public var diffThreshold: Double?
    /// The run rendered only some images: baseline images it didn't upload are skipped, not removed.
    public var selective: Bool
    /// Every image the suite renders; defaults to `tuist-all-image-names.txt` in the directory.
    public var allImageNamesFile: AbsolutePath?
    /// Whether unreviewed or rejected changes fail the command.
    public var failOnChanges: Bool
    public var json: Bool
    public var buildSystem: SnapshotBuildManifest.BuildSystem?

    public init(
        set: String,
        path: AbsolutePath,
        fullHandle: String? = nil,
        diffThreshold: Double? = nil,
        selective: Bool = false,
        allImageNamesFile: AbsolutePath? = nil,
        failOnChanges: Bool = true,
        json: Bool = false,
        buildSystem: SnapshotBuildManifest.BuildSystem? = nil
    ) {
        self.set = set
        self.path = path
        self.fullHandle = fullHandle
        self.diffThreshold = diffThreshold
        self.selective = selective
        self.allImageNamesFile = allImageNamesFile
        self.failOnChanges = failOnChanges
        self.json = json
        self.buildSystem = buildSystem
    }
}

@Mockable
public protocol SnapshotsUploadServicing {
    /// Uploads the images in `directory` as a snapshot build and waits for its verdict. Returns
    /// nil when the directory has no images.
    @discardableResult
    func upload(directory: AbsolutePath, options: SnapshotsUploadOptions) async throws -> ServerSnapshotBuild?
}

/// Uploads the images a snapshot library recorded as a snapshot build, like the Gradle plugin's
/// `tuistUploadSnapshots`: it hashes the images, creates the build with their manifest, uploads
/// the ones the server lacks, completes the build, and polls it until the comparison with the
/// baseline has a verdict.
public struct SnapshotsUploadService: SnapshotsUploadServicing {
    private let snapshotBuildService: SnapshotBuildServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading
    private let gitController: GitControlling
    private let pollInterval: Duration
    private let timeout: Duration

    public init(
        snapshotBuildService: SnapshotBuildServicing = SnapshotBuildService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader(),
        gitController: GitControlling = GitController(),
        pollInterval: Duration = .seconds(2),
        timeout: Duration = .seconds(600)
    ) {
        self.snapshotBuildService = snapshotBuildService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
        self.gitController = gitController
        self.pollInterval = pollInterval
        self.timeout = timeout
    }

    @discardableResult
    // swiftlint:disable:next function_body_length
    public func upload(directory: AbsolutePath, options: SnapshotsUploadOptions) async throws -> ServerSnapshotBuild? {
        guard FileManager.default.fileExists(atPath: directory.pathString) else {
            throw SnapshotsUploadServiceError.missingDirectory(directory)
        }
        let started = ContinuousClock.now
        let images = try await SnapshotImages.collect(directory: directory)
        guard !images.isEmpty else {
            AlertController.current.warning(.alert("No snapshot images in \(directory.pathString); nothing to upload."))
            return nil
        }

        let config = try await configLoader.loadConfig(path: options.path)
        guard let fullHandle = options.fullHandle ?? config.fullHandle else {
            throw SnapshotsUploadServiceError.missingFullHandle
        }
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let gitInfo = try? await gitController.gitInfo(workingDirectory: options.path)
        guard let gitInfo, let sha = gitInfo.sha, !sha.isEmpty else {
            throw SnapshotsUploadServiceError.missingCommit(options.path)
        }
        let allImageNames = SnapshotImages.allImageNames(
            file: options.allImageNamesFile ?? directory.appending(component: SnapshotImages.allImageNamesFile)
        )

        let created = try await snapshotBuildService.createSnapshotBuild(
            fullHandle: fullHandle,
            serverURL: serverURL,
            manifest: SnapshotBuildManifest(
                set: options.set,
                gitCommitSHA: sha,
                gitBranch: gitInfo.branch,
                gitRef: gitInfo.ref,
                gitRemoteURLOrigin: gitInfo.remoteURLOrigin,
                mergeBaseSHA: await gitController.snapshotsMergeBase(gitInfo: gitInfo, workingDirectory: options.path),
                pullRequestNumber: gitInfo.pullRequestNumber,
                pullRequestTitle: Self.pullRequestTitle(environment: Environment.current.variables),
                isCI: Environment.current.isCI,
                selective: options.selective,
                allImageNames: allImageNames,
                buildSystem: options.buildSystem,
                images: images.map { Self.manifest($0.manifest, defaultDiffThreshold: options.diffThreshold) }
            )
        )

        let files = Dictionary(images.map { ($0.manifest.contentHash, $0.path) }, uniquingKeysWith: { first, _ in first })
        let uploads = created.uploads.compactMap { upload in files[upload.contentHash].map { ($0, upload.url) } }
        let concurrency = SnapshotImages.maxConcurrentTransfers
        let sizes = try await uploads.concurrentMap(maxConcurrentTasks: concurrency) { [snapshotBuildService] file, url in
            try await snapshotBuildService.uploadSnapshotImage(file, to: url)
            return SnapshotImages.fileSize(file)
        }
        _ = try await snapshotBuildService.completeSnapshotBuild(
            fullHandle: fullHandle,
            serverURL: serverURL,
            buildID: created.build.id
        )
        let uploaded = ContinuousClock.now
        if !options.json {
            let transfer = SnapshotImages.transferSummary(bytes: sizes.reduce(0, +), duration: uploaded - started)
            AlertController.current.success(
                .alert("Uploaded \(images.count) snapshot images (\(uploads.count) new, \(transfer)) to set '\(options.set)'.")
            )
        }

        let build = try await awaitVerdict(fullHandle: fullHandle, serverURL: serverURL, buildID: created.build.id)
        if options.json {
            try Noora.current.json(SnapshotBuildOutput(build))
        }
        try report(
            build,
            comparison: SnapshotImages.seconds(ContinuousClock.now - uploaded),
            failOnChanges: options.failOnChanges,
            quiet: options.json
        )
        return build
    }

    /// The command's threshold applies only to images whose metadata doesn't set one.
    private static func manifest(_ image: SnapshotImageManifest, defaultDiffThreshold: Double?) -> SnapshotImageManifest {
        guard image.diffThreshold == nil, let defaultDiffThreshold else { return image }
        return SnapshotImageManifest(
            name: image.name,
            contentHash: image.contentHash,
            width: image.width,
            height: image.height,
            displayName: image.displayName,
            group: image.group,
            tags: image.tags,
            diffThreshold: defaultDiffThreshold
        )
    }

    /// Most comparisons finish within a second or two, so the first polls come quickly and back
    /// off to `pollInterval`: a fixed interval left every run waiting for its next tick.
    private func awaitVerdict(fullHandle: String, serverURL: URL, buildID: String) async throws -> ServerSnapshotBuild {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var interval = min(.milliseconds(250), pollInterval)
        while true {
            let build = try await snapshotBuildService.getSnapshotBuild(
                fullHandle: fullHandle,
                serverURL: serverURL,
                buildID: buildID
            )
            if build.status != "processing" || clock.now >= deadline { return build }
            try await Task.sleep(for: interval)
            interval = min(interval * 2, pollInterval)
        }
    }

    private func report(_ build: ServerSnapshotBuild, comparison: String, failOnChanges: Bool, quiet: Bool) throws {
        let summary = [
            "\(build.changedCount) changed",
            "\(build.addedCount) added",
            "\(build.removedCount) removed",
            "\(build.renamedCount) renamed",
            "\(build.unchangedCount) unchanged",
            "\(build.skippedCount) skipped",
        ].joined(separator: ", ")
        let unreviewed: SnapshotsUploadServiceError? = switch build.status {
        case "needs_review": .changesNeedReview(summary: summary, url: build.url)
        case "rejected": .changesRejected(summary: summary, url: build.url)
        default: nil
        }
        if let unreviewed {
            if failOnChanges { throw unreviewed }
            if !quiet { AlertController.current.warning(.alert("\(unreviewed.localizedDescription)")) }
            return
        }
        switch build.status {
        case "failed":
            throw SnapshotsUploadServiceError.comparisonFailed(url: build.url)
        // Passing without a verdict would let unreviewed changes through.
        case "processing":
            throw SnapshotsUploadServiceError.comparisonTimedOut(url: build.url)
        default:
            if !quiet {
                AlertController.current.success(
                    .alert("Snapshots \(build.status) (\(summary), compared in \(comparison)): \(build.url)")
                )
            }
        }
    }

    /// The pull request's title, which only CI knows: GitHub Actions has it in the event payload,
    /// and GitLab in `CI_MERGE_REQUEST_TITLE`.
    static func pullRequestTitle(environment: [String: String]) -> String? {
        if let title = environment["CI_MERGE_REQUEST_TITLE"], !title.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(title.prefix(1024))
        }
        guard let path = environment["GITHUB_EVENT_PATH"],
              let data = FileManager.default.contents(atPath: path),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = (event["pull_request"] as? [String: Any])?["title"] as? String,
              !title.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return String(title.prefix(1024))
    }
}

extension GitControlling {
    /// The merge base with the base branch, from what the checkout has: the server compares a
    /// pull request with the default branch's build there. Without it, the server walks its
    /// commit graph, which test runs and the Gradle plugin upload, or falls back to the default
    /// branch's latest build.
    func snapshotsMergeBase(gitInfo: GitInfo, workingDirectory: AbsolutePath) async -> String? {
        guard gitInfo.baseBranch != nil else { return nil }
        return try? await gitHistory(
            workingDirectory: try topLevelGitDirectory(workingDirectory: workingDirectory),
            headSHA: gitInfo.sha,
            baseBranch: gitInfo.baseBranch,
            limits: GitHistoryLimits(windowDays: 1, windowCommits: 1, deepenBudgetSeconds: 0, remoteAccess: .none)
        ).mergeBaseSHA
    }
}

private struct SnapshotBuildOutput: Codable {
    let id: String
    let url: String
    let status: String
    let changedCount: Int
    let addedCount: Int
    let removedCount: Int
    let renamedCount: Int
    let unchangedCount: Int
    let skippedCount: Int

    init(_ build: ServerSnapshotBuild) {
        id = build.id
        url = build.url
        status = build.status
        changedCount = build.changedCount
        addedCount = build.addedCount
        removedCount = build.removedCount
        renamedCount = build.renamedCount
        unchangedCount = build.unchangedCount
        skippedCount = build.skippedCount
    }

    enum CodingKeys: String, CodingKey {
        case id, url, status
        case changedCount = "changed_count"
        case addedCount = "added_count"
        case removedCount = "removed_count"
        case renamedCount = "renamed_count"
        case unchangedCount = "unchanged_count"
        case skippedCount = "skipped_count"
    }
}
