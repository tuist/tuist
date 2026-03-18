import FileSystem
import Foundation
import Mockable
import Path
import TuistCI
import TuistCore
import TuistLogging
import TuistServer
import TuistSupport

public struct Shard {
    public let testProductsPath: AbsolutePath
    public let modules: [String]
    public let suites: [String: [String]]
    public let selectiveTestingGraph: SelectiveTestingGraph?

    public var testIdentifiers: [String] {
        if suites.isEmpty {
            return modules
        }
        return suites.flatMap { module, suiteNames in
            suiteNames.map { "\(module)/\($0)" }
        }
    }
}

@Mockable
public protocol ShardServicing {
    func shard(
        shardIndex: Int,
        scheme: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> Shard
}

public enum ShardServiceError: LocalizedError, Equatable {
    case cannotDeriveSessionId
    case downloadFailed(String)
    case testProductsNotFound

    public var errorDescription: String? {
        switch self {
        case .cannotDeriveSessionId:
            return "Cannot derive a shard plan ID. Make sure you are running in a supported CI environment."
        case let .downloadFailed(message):
            return "Failed to download shard artifacts: \(message)"
        case .testProductsNotFound:
            return "No .xctestproducts bundle found in the downloaded shard archive."
        }
    }
}

public struct ShardService: ShardServicing {
    private let getShardService: GetShardServicing
    private let ciController: CIControlling
    private let fileSystem: FileSysteming
    private let fileUnarchiver: FileArchivingFactorying

    public init(
        getShardService: GetShardServicing = GetShardService(),
        ciController: CIControlling = CIController(),
        fileSystem: FileSysteming = FileSystem(),
        fileUnarchiver: FileArchivingFactorying = FileArchivingFactory()
    ) {
        self.getShardService = getShardService
        self.ciController = ciController
        self.fileSystem = fileSystem
        self.fileUnarchiver = fileUnarchiver
    }

    public func shard(
        shardIndex: Int,
        scheme: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> Shard {
        guard let planId = ciController.ciInfo()?.shardPlanId else {
            throw ShardServiceError.cannotDeriveSessionId
        }

        Logger.current.debug("Fetching shard \(shardIndex) for plan '\(planId)'...")

        let shard = try await getShardService.getShard(
            fullHandle: fullHandle,
            serverURL: serverURL,
            planId: planId,
            shardIndex: shardIndex
        )

        Logger.current.info("Shard \(shardIndex) assigned modules: \(shard.modules.joined(separator: ", "))")

        let tempDirectory = try await fileSystem.makeTemporaryDirectory(prefix: "tuist-shard")
        let shardZipPath = tempDirectory.appending(component: "shard.zip")
        try await downloadFile(from: shard.download_url, to: shardZipPath)
        Logger.current.debug("Downloaded test products bundle.")

        let unarchiver = try fileUnarchiver.makeFileUnarchiver(for: shardZipPath)
        let unzippedPath = try unarchiver.unzip()

        guard let testProductsPath = try await fileSystem
            .glob(directory: unzippedPath, include: ["*.xctestproducts"])
            .first(where: { _ in true })
        else {
            throw ShardServiceError.testProductsNotFound
        }
        Logger.current.debug("Unzipped test products to \(testProductsPath.pathString)")

        let selectiveTestingGraphPath = testProductsPath.appending(component: SelectiveTestingGraph.fileName)
        var selectiveTestingGraph: SelectiveTestingGraph?
        if try await fileSystem.exists(selectiveTestingGraphPath) {
            selectiveTestingGraph = try? await fileSystem.readJSONFile(at: selectiveTestingGraphPath)
            if selectiveTestingGraph != nil {
                Logger.current.debug("Loaded selective testing graph from test products bundle.")
            }
        }

        return Shard(
            testProductsPath: testProductsPath,
            modules: shard.modules,
            suites: shard.suites.additionalProperties,
            selectiveTestingGraph: selectiveTestingGraph
        )
    }

    private func downloadFile(from urlString: String, to path: AbsolutePath) async throws {
        guard let url = URL(string: urlString) else {
            throw ShardServiceError.downloadFailed("Invalid URL: \(urlString)")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ShardServiceError.downloadFailed("HTTP error downloading \(urlString)")
        }

        try data.write(to: URL(fileURLWithPath: path.pathString))
    }
}
