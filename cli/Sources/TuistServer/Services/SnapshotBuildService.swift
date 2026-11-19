#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Foundation
import Mockable
import OpenAPIRuntime
import Path
import TuistHTTP

/// A snapshot build as the server reports it: where it is in its lifecycle (`state`) and its
/// verdict (`status`), such as `needs_review` when images changed against the baseline and nobody
/// reviewed them yet. Both are open strings: newer servers may send values this client lacks.
public struct ServerSnapshotBuild: Equatable, Sendable, Decodable {
    public let id: String
    public let url: String
    public let state: String
    public let status: String
    public let changedCount: Int
    public let addedCount: Int
    public let removedCount: Int
    public let renamedCount: Int
    public let unchangedCount: Int
    public let skippedCount: Int

    public init(
        id: String,
        url: String,
        state: String,
        status: String,
        changedCount: Int = 0,
        addedCount: Int = 0,
        removedCount: Int = 0,
        renamedCount: Int = 0,
        unchangedCount: Int = 0,
        skippedCount: Int = 0
    ) {
        self.id = id
        self.url = url
        self.state = state
        self.status = status
        self.changedCount = changedCount
        self.addedCount = addedCount
        self.removedCount = removedCount
        self.renamedCount = renamedCount
        self.unchangedCount = unchangedCount
        self.skippedCount = skippedCount
    }

    /// The generated client gives each operation its own copy of the build schema; they all encode
    /// to the same JSON.
    fileprivate init(_ payload: some Encodable) throws {
        self = try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(payload))
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, state, status
        case changedCount = "changed_count"
        case addedCount = "added_count"
        case removedCount = "removed_count"
        case renamedCount = "renamed_count"
        case unchangedCount = "unchanged_count"
        case skippedCount = "skipped_count"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let count = { (key: CodingKeys) in try container.decodeIfPresent(Int.self, forKey: key) ?? 0 }
        self.init(
            id: try container.decode(String.self, forKey: .id),
            url: try container.decode(String.self, forKey: .url),
            state: try container.decode(String.self, forKey: .state),
            status: try container.decode(String.self, forKey: .status),
            changedCount: try count(.changedCount),
            addedCount: try count(.addedCount),
            removedCount: try count(.removedCount),
            renamedCount: try count(.renamedCount),
            unchangedCount: try count(.unchangedCount),
            skippedCount: try count(.skippedCount)
        )
    }
}

/// The build a build uploaded from a checkout would be compared with, and its images to download.
/// `build` is nil while the set has no baseline.
public struct ServerSnapshotBaseline: Equatable, Sendable {
    public struct Image: Equatable, Sendable {
        public let name: String
        public let contentHash: String
        public let url: URL

        public init(name: String, contentHash: String, url: URL) {
            self.name = name
            self.contentHash = contentHash
            self.url = url
        }
    }

    public let build: ServerSnapshotBuild?
    public let images: [Image]

    public init(build: ServerSnapshotBuild?, images: [Image]) {
        self.build = build
        self.images = images
    }
}

/// An image of a snapshot build's manifest. The metadata comes from the JSON file next to the
/// image, in the format Sentry's snapshot uploads use.
public struct SnapshotImageManifest: Equatable, Sendable {
    /// The image's path relative to the uploaded directory.
    public let name: String
    /// The SHA-256 of the PNG.
    public let contentHash: String
    public let width: Int?
    public let height: Int?
    public let displayName: String?
    public let group: String?
    public let tags: [String: String]
    public let diffThreshold: Double?

    public init(
        name: String,
        contentHash: String,
        width: Int? = nil,
        height: Int? = nil,
        displayName: String? = nil,
        group: String? = nil,
        tags: [String: String] = [:],
        diffThreshold: Double? = nil
    ) {
        self.name = name
        self.contentHash = contentHash
        self.width = width
        self.height = height
        self.displayName = displayName
        self.group = group
        self.tags = tags
        self.diffThreshold = diffThreshold
    }
}

/// What a client tells the server about a snapshot build: the set and commit it belongs to, its
/// place in Git history so the server can choose the baseline, and its images.
public struct SnapshotBuildManifest: Equatable, Sendable {
    public enum BuildSystem: String, Sendable {
        case gradle
        case xcode
    }

    public let set: String
    public let gitCommitSHA: String
    public let gitBranch: String?
    public let gitRef: String?
    public let gitRemoteURLOrigin: String?
    public let mergeBaseSHA: String?
    public let pullRequestNumber: Int?
    public let pullRequestTitle: String?
    public let isCI: Bool
    /// The run rendered only some images: baseline images it didn't upload are skipped, not removed.
    public let selective: Bool
    /// Every image the suite renders, for a run that rendered only some.
    public let allImageNames: [String]?
    /// Nil when the client can't tell, such as a directory uploaded from the command line.
    public let buildSystem: BuildSystem?
    public let images: [SnapshotImageManifest]

    public init(
        set: String,
        gitCommitSHA: String,
        gitBranch: String?,
        gitRef: String?,
        gitRemoteURLOrigin: String?,
        mergeBaseSHA: String?,
        pullRequestNumber: Int?,
        pullRequestTitle: String?,
        isCI: Bool,
        selective: Bool,
        allImageNames: [String]?,
        buildSystem: BuildSystem?,
        images: [SnapshotImageManifest]
    ) {
        self.set = set
        self.gitCommitSHA = gitCommitSHA
        self.gitBranch = gitBranch
        self.gitRef = gitRef
        self.gitRemoteURLOrigin = gitRemoteURLOrigin
        self.mergeBaseSHA = mergeBaseSHA
        self.pullRequestNumber = pullRequestNumber
        self.pullRequestTitle = pullRequestTitle
        self.isCI = isCI
        self.selective = selective
        self.allImageNames = allImageNames
        self.buildSystem = buildSystem
        self.images = images
    }
}

/// A created build and the images the server doesn't store yet, each with a presigned URL to PUT
/// the PNG to.
public struct CreatedSnapshotBuild: Equatable, Sendable {
    public struct Upload: Equatable, Sendable {
        public let contentHash: String
        public let url: URL

        public init(contentHash: String, url: URL) {
            self.contentHash = contentHash
            self.url = url
        }
    }

    public let build: ServerSnapshotBuild
    public let uploads: [Upload]

    public init(build: ServerSnapshotBuild, uploads: [Upload]) {
        self.build = build
        self.uploads = uploads
    }
}

enum SnapshotBuildServiceError: Equatable, LocalizedError {
    case unknownError(Int)
    case badRequest(String)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)
    case invalidUploadURL(String)
    case uploadFailed(Int)
    case downloadFailed(Int)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The snapshot build request failed with an unknown Tuist response of \(statusCode)."
        case let .badRequest(message), let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        case let .invalidUploadURL(url):
            return "The server returned an invalid presigned snapshot URL: \(url)"
        case let .uploadFailed(statusCode):
            return "Uploading a snapshot image failed with HTTP \(statusCode)."
        case let .downloadFailed(statusCode):
            return "Downloading a snapshot image failed with HTTP \(statusCode)."
        }
    }
}

@Mockable
public protocol SnapshotBuildServicing: Sendable {
    func createSnapshotBuild(
        fullHandle: String,
        serverURL: URL,
        manifest: SnapshotBuildManifest
    ) async throws -> CreatedSnapshotBuild

    /// PUTs a PNG to a presigned URL from `createSnapshotBuild`.
    func uploadSnapshotImage(_ file: AbsolutePath, to url: URL) async throws

    func completeSnapshotBuild(fullHandle: String, serverURL: URL, buildID: String) async throws -> ServerSnapshotBuild

    func getSnapshotBuild(fullHandle: String, serverURL: URL, buildID: String) async throws -> ServerSnapshotBuild

    /// The baseline a build of `set` uploaded from the checkout at `gitCommitSHA` would be compared with.
    func getSnapshotBaseline(
        fullHandle: String,
        serverURL: URL,
        set: String,
        gitCommitSHA: String,
        mergeBaseSHA: String?,
        gitRemoteURLOrigin: String?
    ) async throws -> ServerSnapshotBaseline

    /// GETs a PNG from a presigned URL from `getSnapshotBaseline` to `file`, replacing it.
    func downloadSnapshotImage(from url: URL, to file: AbsolutePath) async throws
}

/// The client's side of the snapshot API: create a build from the manifest of its images, upload
/// the images the server lacks, complete the build, and poll it for the verdict.
public struct SnapshotBuildService: SnapshotBuildServicing {
    private let fullHandleService: FullHandleServicing
    private let transfer: RetryingURLTransfer

    public init(
        fullHandleService: FullHandleServicing = FullHandleService(),
        urlSession: URLSession = .tuistShared
    ) {
        self.fullHandleService = fullHandleService
        transfer = RetryingURLTransfer(urlSession: urlSession)
    }

    // swiftlint:disable:next function_body_length
    public func createSnapshotBuild(
        fullHandle: String,
        serverURL: URL,
        manifest: SnapshotBuildManifest
    ) async throws -> CreatedSnapshotBuild {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.createSnapshotBuild(
            .init(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                body: .json(
                    .init(
                        all_image_names: manifest.allImageNames,
                        build_system: manifest.buildSystem.flatMap { .init(rawValue: $0.rawValue) },
                        git_branch: manifest.gitBranch,
                        git_commit_sha: manifest.gitCommitSHA,
                        git_ref: manifest.gitRef,
                        git_remote_url_origin: manifest.gitRemoteURLOrigin,
                        images: manifest.images.map { image in
                            .init(
                                content_hash: image.contentHash,
                                diff_threshold: image.diffThreshold,
                                display_name: image.displayName,
                                group: image.group,
                                height: image.height,
                                name: image.name,
                                tags: image.tags.isEmpty ? nil : .init(additionalProperties: image.tags),
                                width: image.width
                            )
                        },
                        is_ci: manifest.isCI,
                        merge_base_sha: manifest.mergeBaseSHA,
                        pull_request_number: manifest.pullRequestNumber,
                        pull_request_title: manifest.pullRequestTitle,
                        selective: manifest.selective,
                        set: manifest.set
                    )
                )
            )
        )
        switch response {
        case let .ok(ok):
            switch ok.body {
            case let .json(json):
                return CreatedSnapshotBuild(
                    build: try ServerSnapshotBuild(json.build),
                    uploads: try json.uploads.map { upload in
                        guard let url = URL(string: upload.url) else {
                            throw SnapshotBuildServiceError.invalidUploadURL(upload.url)
                        }
                        return .init(contentHash: upload.content_hash, url: url)
                    }
                )
            }
        case let .badRequest(error):
            switch error.body {
            case let .json(error): throw SnapshotBuildServiceError.badRequest(error.message)
            }
        case let .notFound(error):
            switch error.body {
            case let .json(error): throw SnapshotBuildServiceError.notFound(error.message)
            }
        case let .forbidden(error):
            switch error.body {
            case let .json(error): throw SnapshotBuildServiceError.forbidden(error.message)
            }
        case let .unauthorized(error):
            switch error.body {
            case let .json(error): throw SnapshotBuildServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode, _):
            throw SnapshotBuildServiceError.unknownError(statusCode)
        }
    }

    public func uploadSnapshotImage(_ file: AbsolutePath, to url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        request.addAzureBlobTypeHeaderIfNeeded()
        // Content-addressed: putting the same bytes again changes nothing, so retrying is safe.
        let (_, response) = try await transfer.upload(request, fromFile: URL(fileURLWithPath: file.pathString))
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(statusCode) else { throw SnapshotBuildServiceError.uploadFailed(statusCode) }
    }

    public func completeSnapshotBuild(fullHandle: String, serverURL: URL, buildID: String) async throws -> ServerSnapshotBuild {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.completeSnapshotBuild(
            .init(path: .init(
                account_handle: handles.accountHandle,
                project_handle: handles.projectHandle,
                build_id: buildID
            ))
        )
        switch response {
        case let .ok(ok):
            switch ok.body {
            case let .json(json): return try ServerSnapshotBuild(json)
            }
        case let .badRequest(error):
            switch error.body {
            case let .json(error): throw SnapshotBuildServiceError.badRequest(error.message)
            }
        case let .notFound(error):
            switch error.body {
            case let .json(error): throw SnapshotBuildServiceError.notFound(error.message)
            }
        case let .forbidden(error):
            switch error.body {
            case let .json(error): throw SnapshotBuildServiceError.forbidden(error.message)
            }
        case let .unauthorized(error):
            switch error.body {
            case let .json(error): throw SnapshotBuildServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode, _):
            throw SnapshotBuildServiceError.unknownError(statusCode)
        }
    }

    public func getSnapshotBuild(fullHandle: String, serverURL: URL, buildID: String) async throws -> ServerSnapshotBuild {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.getSnapshotBuild(
            .init(path: .init(
                account_handle: handles.accountHandle,
                project_handle: handles.projectHandle,
                build_id: buildID
            ))
        )
        switch response {
        case let .ok(ok):
            switch ok.body {
            case let .json(json): return try ServerSnapshotBuild(json)
            }
        case let .notFound(error):
            switch error.body {
            case let .json(error): throw SnapshotBuildServiceError.notFound(error.message)
            }
        case let .forbidden(error):
            switch error.body {
            case let .json(error): throw SnapshotBuildServiceError.forbidden(error.message)
            }
        case let .unauthorized(error):
            switch error.body {
            case let .json(error): throw SnapshotBuildServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode, _):
            throw SnapshotBuildServiceError.unknownError(statusCode)
        }
    }

    public func getSnapshotBaseline(
        fullHandle: String,
        serverURL: URL,
        set: String,
        gitCommitSHA: String,
        mergeBaseSHA: String?,
        gitRemoteURLOrigin: String?
    ) async throws -> ServerSnapshotBaseline {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.getSnapshotBaseline(
            .init(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                query: .init(
                    set: set,
                    git_commit_sha: gitCommitSHA,
                    merge_base_sha: mergeBaseSHA,
                    git_remote_url_origin: gitRemoteURLOrigin
                )
            )
        )
        switch response {
        case let .ok(ok):
            switch ok.body {
            case let .json(json):
                return ServerSnapshotBaseline(
                    build: try json.build.map { try ServerSnapshotBuild($0) },
                    images: try json.images.map { image in
                        guard let url = URL(string: image.url) else {
                            throw SnapshotBuildServiceError.invalidUploadURL(image.url)
                        }
                        return .init(name: image.name, contentHash: image.content_hash, url: url)
                    }
                )
            }
        case let .notFound(error):
            switch error.body {
            case let .json(error): throw SnapshotBuildServiceError.notFound(error.message)
            }
        case let .forbidden(error):
            switch error.body {
            case let .json(error): throw SnapshotBuildServiceError.forbidden(error.message)
            }
        case let .unauthorized(error):
            switch error.body {
            case let .json(error): throw SnapshotBuildServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode, _):
            throw SnapshotBuildServiceError.unknownError(statusCode)
        }
    }

    public func downloadSnapshotImage(from url: URL, to file: AbsolutePath) async throws {
        let (downloaded, response) = try await transfer.download(URLRequest(url: url))
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(statusCode) else {
            try? FileManager.default.removeItem(at: downloaded)
            throw SnapshotBuildServiceError.downloadFailed(statusCode)
        }
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: file.parentDirectory.pathString),
            withIntermediateDirectories: true
        )
        _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: file.pathString), withItemAt: downloaded)
    }
}
