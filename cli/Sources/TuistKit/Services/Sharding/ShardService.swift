import FileSystem
import Foundation
import Mockable
import Path
import TuistAppleArchiver
import TuistCI
import TuistCore
import TuistHTTP
import TuistLogging
import TuistServer
import TuistSupport

public struct Shard {
    public let reference: String
    public let shardPlanId: String
    public let testProductsPath: AbsolutePath
    /// xcodebuild `-only-testing` identifiers selecting this shard's work. Suite granularity yields
    /// `Module/Suite` entries; module granularity yields bare `Module` entries.
    public let testIdentifiers: [String]
    /// xcodebuild `-skip-testing` identifiers. Non-empty only on the catch-all shard, which carries no
    /// `-only-testing` and instead skips every suite assigned to other shards — so it runs everything
    /// NOT explicitly assigned (newly added or un-enumerated suites included) rather than dropping it.
    public let skipTestIdentifiers: [String]
    public let modules: [String]
    public let selectiveTestingGraph: SelectiveTestingGraph?
    /// For plans of a coverage-based test selection run: the tests in this shard's work that
    /// selection skipped.
    public var skippedTests: [SkippedTest] = []
}

@Mockable
public protocol ShardServicing {
    func shard(
        shardIndex: Int,
        fullHandle: String,
        serverURL: URL,
        reference: String?,
        shardPlanId: String?,
        testProductsPath: AbsolutePath?,
        testProductsArchivePath: AbsolutePath?
    ) async throws -> Shard
}

public enum ShardServiceError: LocalizedError, Equatable {
    case cannotDeriveReference
    case invalidDownloadURL(String)

    public var errorDescription: String? {
        switch self {
        case .cannotDeriveReference:
            return
                "Cannot derive a shard plan reference. Pass --shard-reference explicitly or run in a supported CI environment (GitHub Actions, GitLab CI, CircleCI, Buildkite, Codemagic)."
        case let .invalidDownloadURL(url):
            return "Invalid shard download URL: \(url)"
        }
    }
}

public struct ShardService: ShardServicing {
    /// The most shard artifacts downloading at once, each over `FileClient.parallelRangeLanes` connections.
    static let artifactDownloadsAhead = 3

    private let getShardService: GetShardServicing
    private let ciController: CIControlling
    private let fileClient: FileClienting
    private let fileSystem: FileSysteming
    private let appleArchiver: AppleArchiving
    private let retryProvider: RetryProviding

    public init(
        getShardService: GetShardServicing = GetShardService(),
        ciController: CIControlling = CIController(),
        fileClient: FileClienting = FileClient(),
        fileSystem: FileSysteming = FileSystem(),
        appleArchiver: AppleArchiving = AppleArchiver(),
        retryProvider: RetryProviding = RetryProvider()
    ) {
        self.getShardService = getShardService
        self.ciController = ciController
        self.fileClient = fileClient
        self.fileSystem = fileSystem
        self.appleArchiver = appleArchiver
        self.retryProvider = retryProvider
    }

    public func shard(
        shardIndex: Int,
        fullHandle: String,
        serverURL: URL,
        reference: String? = nil,
        shardPlanId: String? = nil,
        testProductsPath: AbsolutePath? = nil,
        testProductsArchivePath: AbsolutePath? = nil
    ) async throws -> Shard {
        let shardPlanId = shardPlanId.flatMap { $0.isEmpty ? nil : $0 }
        guard let reference = reference ?? ciController.ciInfo()?.shardReference ?? shardPlanId else {
            throw ShardServiceError.cannotDeriveReference
        }

        Logger.current.debug("Fetching shard \(shardIndex) for plan '\(reference)'...")

        let shard = try await getShardService.getShard(
            fullHandle: fullHandle,
            serverURL: serverURL,
            reference: reference,
            shardPlanId: shardPlanId,
            shardIndex: shardIndex
        )

        // A reference identifies the CI run rather than the build job inside it, so a workflow that
        // builds more than one plan per run can resolve a plan another job created. The suites
        // printed below are what shows that; the identifier is here for pinning it down after.
        Logger.current.debug("Resolved shard plan \(shard.shard_plan_id)")

        let suites = shard.suites.additionalProperties
        let skipTestIdentifiers = shard.skip ?? []
        Logger.current.notice(
            "Shard \(shardIndex): \(noticeIdentifiers(modules: shard.modules, suites: suites, skipTestIdentifiers: skipTestIdentifiers).joined(separator: ", "))",
            metadata: .section
        )

        let resolvedTestProductsPath: AbsolutePath

        if let testProductsPath {
            resolvedTestProductsPath = testProductsPath
            Logger.current.debug("Using local test products at \(testProductsPath.pathString)")
        } else if let testProductsArchivePath {
            let extractedTestProductsPath = try await fileSystem.makeTemporaryDirectory(prefix: "tuist-shard-unzip")
            try await appleArchiver.decompress(archive: testProductsArchivePath, to: extractedTestProductsPath)
            resolvedTestProductsPath = try await normalizeExtractedTestProductsPath(extractedTestProductsPath)
            Logger.current.debug("Extracted local shard archive to \(resolvedTestProductsPath.pathString)")
        } else {
            let extractedTestProductsPath = try await fileSystem.makeTemporaryDirectory(prefix: "tuist-shard-unzip")
            let downloadURLs = try shard.download_urls.map { downloadURLString in
                guard let downloadURL = URL(string: downloadURLString) else {
                    throw ShardServiceError.invalidDownloadURL(downloadURLString)
                }
                return downloadURL
            }
            try await fileSystem.runInTemporaryDirectory(prefix: "tuist-shard-downloads") { downloadedArtifactsPath in
                // The shard's products are split across artifacts (a shared bundle plus one per module
                // assigned to the shard), extracted into a single merged directory. Downloads run ahead of
                // extraction, so the network stays busy while an artifact decompresses, and extraction still
                // applies the artifacts in plan order.
                let archivePaths = downloadURLs.indices.map {
                    downloadedArtifactsPath.appending(component: "artifact-\($0).aar")
                }
                try await withThrowingTaskGroup(of: Int.self) { group in
                    let fileClient = fileClient
                    let retryProvider = retryProvider
                    var started = 0
                    func startDownload() {
                        let index = started
                        started += 1
                        group.addTask {
                            try await retryProvider.runWithRetries {
                                try await fileClient.downloadInParallel(url: downloadURLs[index], to: archivePaths[index])
                            }
                            return index
                        }
                    }
                    while started < min(Self.artifactDownloadsAhead, downloadURLs.count) {
                        startDownload()
                    }
                    var downloaded = Set<Int>()
                    for index in downloadURLs.indices {
                        while !downloaded.contains(index), let finished = try await group.next() {
                            downloaded.insert(finished)
                            if started < downloadURLs.count { startDownload() }
                        }
                        try await appleArchiver.decompress(archive: archivePaths[index], to: extractedTestProductsPath)
                        try? await fileSystem.remove(archivePaths[index])
                    }
                }
            }
            Logger.current.debug("Downloaded \(shard.download_urls.count) test products artifact(s).")
            resolvedTestProductsPath = try await normalizeExtractedTestProductsPath(extractedTestProductsPath)
            Logger.current.debug("Extracted test products to \(resolvedTestProductsPath.pathString)")
        }

        // Selection is delegated to xcodebuild's `-only-testing` arguments rather than rewriting the
        // bundle's `.xctestrun`. xctestrun-level `OnlyTestIdentifiers` does not filter Swift Testing
        // tests, so a rewritten xctestrun silently runs zero tests for Swift Testing suites.
        let testIdentifiers: [String]
        if suites.isEmpty {
            testIdentifiers = shard.modules.sorted()
        } else {
            testIdentifiers = suites
                .flatMap { module, suiteNames in
                    suiteNames.map { "\(module)/\($0)" }
                }
                .sorted()
        }

        let selectiveTestingGraphPath = resolvedTestProductsPath.appending(component: SelectiveTestingGraph.fileName)
        var selectiveTestingGraph: SelectiveTestingGraph?
        if try await fileSystem.exists(selectiveTestingGraphPath) {
            selectiveTestingGraph = try? await fileSystem.readJSONFile(at: selectiveTestingGraphPath)
            if selectiveTestingGraph != nil {
                Logger.current.debug("Loaded selective testing graph from test products bundle.")
            }
        }

        return Shard(
            reference: reference,
            shardPlanId: shard.shard_plan_id,
            testProductsPath: resolvedTestProductsPath,
            testIdentifiers: testIdentifiers,
            skipTestIdentifiers: skipTestIdentifiers,
            modules: shard.modules,
            selectiveTestingGraph: selectiveTestingGraph,
            skippedTests: (shard.skipped_tests ?? []).map {
                SkippedTest(module: $0.module, suite: $0.suite, name: $0.name)
            }
        )
    }

    private func normalizeExtractedTestProductsPath(_ extractedPath: AbsolutePath) async throws -> AbsolutePath {
        guard !extractedPath.basename.hasSuffix(".xctestproducts") else {
            return extractedPath
        }

        let normalizedPath = extractedPath.parentDirectory
            .appending(component: "\(extractedPath.basename).xctestproducts")
        try await fileSystem.move(from: extractedPath, to: normalizedPath)
        return normalizedPath
    }

    private func noticeIdentifiers(
        modules: [String],
        suites: [String: [String]],
        skipTestIdentifiers: [String]
    ) -> [String] {
        if !suites.isEmpty {
            return suites
                .flatMap { module, suiteNames in
                    suiteNames.map { "\(module)/\($0)" }
                }
                .sorted()
        } else if !modules.isEmpty {
            return modules.sorted()
        } else {
            return skipTestIdentifiers.sorted()
        }
    }
}
