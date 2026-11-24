import Foundation
import Mockable
import Noora
import Path
import TuistAlert
import TuistConfigLoader
import TuistGit
import TuistServer
import TuistSupport

enum SnapshotsDownloadServiceError: Equatable, LocalizedError {
    case invalidImageName(String)

    var errorDescription: String? {
        switch self {
        case let .invalidImageName(name):
            return "The baseline has an image named \(name), which isn't a path inside the output directory."
        }
    }
}

public struct SnapshotsDownloadOptions: Equatable, Sendable {
    public var set: String
    /// The Tuist project's directory, which also locates the Git checkout.
    public var path: AbsolutePath
    public var fullHandle: String?
    public var json: Bool

    public init(set: String, path: AbsolutePath, fullHandle: String? = nil, json: Bool = false) {
        self.set = set
        self.path = path
        self.fullHandle = fullHandle
        self.json = json
    }
}

@Mockable
public protocol SnapshotsDownloadServicing {
    /// Writes the baseline images of `options.set` for the current checkout to `directory`.
    @discardableResult
    func download(directory: AbsolutePath, options: SnapshotsDownloadOptions) async throws -> ServerSnapshotBaseline
}

/// Downloads the baseline a build uploaded from the current checkout would be compared with, so
/// snapshot libraries that compare in the test process (swift-snapshot-testing, Paparazzi's
/// verify, Roborazzi) can verify against it without keeping reference images in the repository.
/// Images are written by name, the same names the upload sends, and files already holding the
/// right content are left alone, so a warm directory downloads only what changed.
public struct SnapshotsDownloadService: SnapshotsDownloadServicing {
    private let snapshotBuildService: SnapshotBuildServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading
    private let gitController: GitControlling

    public init(
        snapshotBuildService: SnapshotBuildServicing = SnapshotBuildService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader(),
        gitController: GitControlling = GitController()
    ) {
        self.snapshotBuildService = snapshotBuildService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
        self.gitController = gitController
    }

    @discardableResult
    public func download(directory: AbsolutePath, options: SnapshotsDownloadOptions) async throws -> ServerSnapshotBaseline {
        let config = try await configLoader.loadConfig(path: options.path)
        guard let fullHandle = options.fullHandle ?? config.fullHandle else {
            throw SnapshotsUploadServiceError.missingFullHandle
        }
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        let gitInfo = try? await gitController.gitInfo(workingDirectory: options.path)
        guard let gitInfo, let sha = gitInfo.sha, !sha.isEmpty else {
            throw SnapshotsUploadServiceError.missingCommit(options.path)
        }

        let baseline = try await snapshotBuildService.getSnapshotBaseline(
            fullHandle: fullHandle,
            serverURL: serverURL,
            set: options.set,
            gitCommitSHA: sha,
            mergeBaseSHA: await gitController.snapshotsMergeBase(gitInfo: gitInfo, workingDirectory: options.path),
            gitRemoteURLOrigin: gitInfo.remoteURLOrigin
        )
        guard let build = baseline.build else {
            if !options.json {
                AlertController.current.warning(.alert(
                    "The snapshot set '\(options.set)' has no baseline yet: upload it from the default branch first."
                ))
            } else {
                try Noora.current.json(SnapshotsDownloadOutput(baseline: baseline, downloaded: 0))
            }
            return baseline
        }

        let files = try baseline.images.map { image in (image, try Self.destination(of: image.name, in: directory)) }
        let stale = files.filter { image, file in Self.contentHash(of: file) != image.contentHash }
        let started = ContinuousClock.now
        let concurrency = SnapshotImages.maxConcurrentTransfers
        let sizes = try await stale.concurrentMap(maxConcurrentTasks: concurrency) { [snapshotBuildService] image, file in
            try await snapshotBuildService.downloadSnapshotImage(from: image.url, to: file)
            return SnapshotImages.fileSize(file)
        }
        let transfer = SnapshotImages.transferSummary(bytes: sizes.reduce(0, +), duration: ContinuousClock.now - started)

        if options.json {
            try Noora.current.json(SnapshotsDownloadOutput(baseline: baseline, downloaded: stale.count))
        } else {
            AlertController.current.success(.alert(
                "Downloaded the baseline of set '\(options.set)' to \(directory.pathString): \(baseline.images.count) images, \(stale.count) new or changed (\(transfer)). See \(build.url)"
            ))
        }
        return baseline
    }

    /// The server only stores relative names without `..`; checked again so a response can't
    /// write outside the directory.
    private static func destination(of name: String, in directory: AbsolutePath) throws -> AbsolutePath {
        let components = name.split(separator: "/")
        guard !name.hasPrefix("/"), !components.isEmpty, !components.contains(".."), !components.contains("."),
              let relative = try? RelativePath(validating: name)
        else { throw SnapshotsDownloadServiceError.invalidImageName(name) }
        return directory.appending(relative)
    }

    private static func contentHash(of file: AbsolutePath) -> String? {
        FileManager.default.contents(atPath: file.pathString).map(SnapshotImages.contentHash)
    }
}

private struct SnapshotsDownloadOutput: Codable {
    let buildID: String?
    let url: String?
    let images: Int
    let downloaded: Int

    init(baseline: ServerSnapshotBaseline, downloaded: Int) {
        buildID = baseline.build?.id
        url = baseline.build?.url
        images = baseline.images.count
        self.downloaded = downloaded
    }

    enum CodingKeys: String, CodingKey {
        case buildID = "build_id"
        case url, images, downloaded
    }
}
