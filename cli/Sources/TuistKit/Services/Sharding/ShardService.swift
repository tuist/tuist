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
    public let testTargets: [String]
    public let selectiveTestingGraph: SelectiveTestingGraph?
}

@Mockable
public protocol ShardServicing {
    func shard(
        shardIndex: Int,
        scheme: String,
        fullHandle: String,
        serverURL: URL,
        outputPath: AbsolutePath
    ) async throws -> Shard
}

public enum ShardServiceError: LocalizedError, Equatable {
    case cannotDeriveSessionId
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cannotDeriveSessionId:
            return "Cannot derive a shard plan ID. Make sure you are running in a supported CI environment."
        case let .downloadFailed(message):
            return "Failed to download shard artifacts: \(message)"
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
        serverURL: URL,
        outputPath: AbsolutePath
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

        Logger.current.info("Shard \(shardIndex) assigned targets: \(shard.test_targets.joined(separator: ", "))")

        let bundleZipPath = outputPath.appending(component: "\(scheme).xctestproducts.zip")
        try await downloadFile(from: shard.bundle_download_url, to: bundleZipPath)
        Logger.current.debug("Downloaded test products bundle.")

        let unarchiver = try fileUnarchiver.makeFileUnarchiver(for: bundleZipPath)
        let unzippedPath = try unarchiver.unzip()

        let bundlePath: AbsolutePath
        if let found = try await fileSystem.glob(directory: unzippedPath, include: ["*.xctestproducts"])
            .first(where: { _ in true })
        {
            bundlePath = found
        } else {
            bundlePath = unzippedPath
        }
        Logger.current.debug("Unzipped test products to \(bundlePath.pathString)")

        let xcTestRunPath = outputPath.appending(component: "\(scheme).xctestrun")
        try await downloadFile(from: shard.xctestrun_download_url, to: xcTestRunPath)
        Logger.current.debug("Downloaded filtered .xctestrun file.")

        let targetXCTestRunPath = bundlePath.appending(component: "\(scheme).xctestrun")
        if try await fileSystem.exists(targetXCTestRunPath) {
            try await fileSystem.remove(targetXCTestRunPath)
        }
        try await fileSystem.copy(xcTestRunPath, to: targetXCTestRunPath)

        let selectiveTestingGraphPath = bundlePath.appending(component: SelectiveTestingGraph.fileName)
        var selectiveTestingGraph: SelectiveTestingGraph?
        if try await fileSystem.exists(selectiveTestingGraphPath) {
            selectiveTestingGraph = try? await fileSystem.readJSONFile(at: selectiveTestingGraphPath)
            if selectiveTestingGraph != nil {
                Logger.current.debug("Loaded selective testing graph from test products bundle.")
            }
        }

        return Shard(
            testProductsPath: bundlePath,
            testTargets: shard.test_targets,
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
