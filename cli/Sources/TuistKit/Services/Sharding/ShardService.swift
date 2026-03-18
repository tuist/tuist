import FileSystem
import Foundation
import Mockable
import Path
import TuistCI
import TuistCore
import TuistHTTP
import TuistLogging
import TuistServer
import TuistSupport

public struct Shard {
    public let planId: String
    public let testProductsPath: AbsolutePath
    public let modules: [String]
    public let selectiveTestingGraph: SelectiveTestingGraph?
}

@Mockable
public protocol ShardServicing {
    func shard(
        shardIndex: Int,
        fullHandle: String,
        serverURL: URL
    ) async throws -> Shard
}

public enum ShardServiceError: LocalizedError, Equatable {
    case cannotDeriveSessionId
    case invalidDownloadURL(String)
    case testProductsNotFound
    case invalidXCTestRun

    public var errorDescription: String? {
        switch self {
        case .cannotDeriveSessionId:
            return "Cannot derive a shard plan ID. Make sure you are running in a supported CI environment."
        case let .invalidDownloadURL(url):
            return "Invalid shard download URL: \(url)"
        case .testProductsNotFound:
            return "No .xctestproducts bundle found in the downloaded shard archive."
        case .invalidXCTestRun:
            return "The .xctestrun file has an invalid format."
        }
    }
}

public struct ShardService: ShardServicing {
    private let getShardService: GetShardServicing
    private let ciController: CIControlling
    private let fileClient: FileClienting
    private let fileSystem: FileSysteming
    private let fileUnarchiver: FileArchivingFactorying

    public init(
        getShardService: GetShardServicing = GetShardService(),
        ciController: CIControlling = CIController(),
        fileClient: FileClienting = FileClient(),
        fileSystem: FileSysteming = FileSystem(),
        fileUnarchiver: FileArchivingFactorying = FileArchivingFactory()
    ) {
        self.getShardService = getShardService
        self.ciController = ciController
        self.fileClient = fileClient
        self.fileSystem = fileSystem
        self.fileUnarchiver = fileUnarchiver
    }

    public func shard(
        shardIndex: Int,
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

        guard let downloadURL = URL(string: shard.download_url) else {
            throw ShardServiceError.invalidDownloadURL(shard.download_url)
        }
        let shardZipPath = try await fileClient.download(url: downloadURL)
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

        let xcTestRunPaths = try await fileSystem
            .glob(directory: testProductsPath, include: ["**/*.xctestrun"])
            .collect()
        for xcTestRunPath in xcTestRunPaths {
            let plistData = try await fileSystem.readFile(at: xcTestRunPath)
            let filteredData = try filterXCTestRun(
                plistData: plistData,
                modules: shard.modules,
                suites: shard.suites.additionalProperties
            )
            try filteredData.write(to: URL(fileURLWithPath: xcTestRunPath.pathString))
        }

        let selectiveTestingGraphPath = testProductsPath.appending(component: SelectiveTestingGraph.fileName)
        var selectiveTestingGraph: SelectiveTestingGraph?
        if try await fileSystem.exists(selectiveTestingGraphPath) {
            selectiveTestingGraph = try? await fileSystem.readJSONFile(at: selectiveTestingGraphPath)
            if selectiveTestingGraph != nil {
                Logger.current.debug("Loaded selective testing graph from test products bundle.")
            }
        }

        return Shard(
            planId: planId,
            testProductsPath: testProductsPath,
            modules: shard.modules,
            selectiveTestingGraph: selectiveTestingGraph
        )
    }

    func filterXCTestRun(
        plistData data: Data,
        modules: [String],
        suites: [String: [String]]
    ) throws -> Data {
        guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ShardServiceError.invalidXCTestRun
        }
        guard var configurations = plist["TestConfigurations"] as? [[String: Any]] else {
            throw ShardServiceError.invalidXCTestRun
        }

        let moduleSet = Set(modules)

        configurations = configurations.map { config in
            var config = config
            guard var targets = config["TestTargets"] as? [[String: Any]] else { return config }

            targets = targets.filter { target in
                guard let name = target["BlueprintName"] as? String else { return false }
                return moduleSet.contains(name)
            }

            if !suites.isEmpty {
                targets = targets.map { target in
                    var target = target
                    if let name = target["BlueprintName"] as? String,
                       let suiteNames = suites[name]
                    {
                        target["OnlyTestIdentifiers"] = suiteNames
                    }
                    return target
                }
            }

            config["TestTargets"] = targets
            return config
        }

        plist["TestConfigurations"] = configurations
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
