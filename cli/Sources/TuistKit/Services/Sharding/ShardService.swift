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
    /// Whether `testProductsPath` is a temporary directory owned by Tuist (downloaded or extracted)
    /// and therefore safe to delete after the run. `false` when it points at user-provided products.
    public let testProductsAreTemporary: Bool
    /// xcodebuild `-only-testing` identifiers selecting this shard's work. Suite granularity yields
    /// `Module/Suite` entries; module granularity yields bare `Module` entries.
    public let testIdentifiers: [String]
    public let modules: [String]
    public let selectiveTestingGraph: SelectiveTestingGraph?
}

@Mockable
public protocol ShardServicing {
    func shard(
        shardIndex: Int,
        fullHandle: String,
        serverURL: URL,
        reference: String?,
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
    private let getShardService: GetShardServicing
    private let ciController: CIControlling
    private let fileClient: FileClienting
    private let fileSystem: FileSysteming
    private let appleArchiver: AppleArchiving

    public init(
        getShardService: GetShardServicing = GetShardService(),
        ciController: CIControlling = CIController(),
        fileClient: FileClienting = FileClient(),
        fileSystem: FileSysteming = FileSystem(),
        appleArchiver: AppleArchiving = AppleArchiver()
    ) {
        self.getShardService = getShardService
        self.ciController = ciController
        self.fileClient = fileClient
        self.fileSystem = fileSystem
        self.appleArchiver = appleArchiver
    }

    public func shard(
        shardIndex: Int,
        fullHandle: String,
        serverURL: URL,
        reference: String? = nil,
        testProductsPath: AbsolutePath? = nil,
        testProductsArchivePath: AbsolutePath? = nil
    ) async throws -> Shard {
        guard let reference = reference ?? ciController.ciInfo()?.shardReference else {
            throw ShardServiceError.cannotDeriveReference
        }

        Logger.current.debug("Fetching shard \(shardIndex) for plan '\(reference)'...")

        let shard = try await getShardService.getShard(
            fullHandle: fullHandle,
            serverURL: serverURL,
            reference: reference,
            shardIndex: shardIndex
        )

        let suites = shard.suites.additionalProperties
        if suites.isEmpty {
            Logger.current.notice("Shard \(shardIndex): \(shard.modules.joined(separator: ", "))", metadata: .section)
        } else {
            let names = suites.values.flatMap { $0 }.sorted()
            Logger.current.notice("Shard \(shardIndex): \(names.joined(separator: ", "))", metadata: .section)
        }

        let resolvedTestProductsPath: AbsolutePath
        let testProductsAreTemporary: Bool

        if let testProductsPath {
            resolvedTestProductsPath = testProductsPath
            testProductsAreTemporary = false
            Logger.current.debug("Using local test products at \(testProductsPath.pathString)")
        } else if let testProductsArchivePath {
            let extractedTestProductsPath = try await fileSystem.makeTemporaryDirectory(prefix: "tuist-shard-unzip")
            try await appleArchiver.decompress(archive: testProductsArchivePath, to: extractedTestProductsPath)
            resolvedTestProductsPath = try await normalizeExtractedTestProductsPath(extractedTestProductsPath)
            testProductsAreTemporary = true
            Logger.current.debug("Extracted local shard archive to \(resolvedTestProductsPath.pathString)")
        } else {
            guard let downloadURL = URL(string: shard.download_url) else {
                throw ShardServiceError.invalidDownloadURL(shard.download_url)
            }
            let shardArchivePath = try await fileClient.download(url: downloadURL)
            Logger.current.debug("Downloaded test products bundle.")

            let extractedTestProductsPath = try await fileSystem.makeTemporaryDirectory(prefix: "tuist-shard-unzip")
            try await appleArchiver.decompress(archive: shardArchivePath, to: extractedTestProductsPath)
            try? await fileSystem.remove(shardArchivePath)
            resolvedTestProductsPath = try await normalizeExtractedTestProductsPath(extractedTestProductsPath)
            testProductsAreTemporary = true
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
                .flatMap { module, suiteNames in suiteNames.map { "\(module)/\($0)" } }
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
            testProductsAreTemporary: testProductsAreTemporary,
            testIdentifiers: testIdentifiers,
            modules: shard.modules,
            selectiveTestingGraph: selectiveTestingGraph
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
}
