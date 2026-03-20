import Command
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
    public let reference: String
    public let shardPlanId: String
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
    case cannotDeriveReference
    case invalidDownloadURL(String)
    case testProductsNotFound
    case invalidXCTestRun

    public var errorDescription: String? {
        switch self {
        case .cannotDeriveReference:
            return
                "Cannot derive a shard plan reference. Pass --shard-reference explicitly or run in a supported CI environment (GitHub Actions, GitLab CI, CircleCI, Buildkite, Codemagic)."
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
    private let commandRunner: CommandRunning

    public init(
        getShardService: GetShardServicing = GetShardService(),
        ciController: CIControlling = CIController(),
        fileClient: FileClienting = FileClient(),
        fileSystem: FileSysteming = FileSystem(),
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.getShardService = getShardService
        self.ciController = ciController
        self.fileClient = fileClient
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    public func shard(
        shardIndex: Int,
        fullHandle: String,
        serverURL: URL
    ) async throws -> Shard {
        guard let reference = ciController.ciInfo()?.shardReference else {
            throw ShardServiceError.cannotDeriveReference
        }

        Logger.current.debug("Fetching shard \(shardIndex) for plan '\(reference)'...")

        let shard = try await getShardService.getShard(
            fullHandle: fullHandle,
            serverURL: serverURL,
            reference: reference,
            shardIndex: shardIndex
        )

        Logger.current.info("Shard \(shardIndex) assigned modules: \(shard.modules.joined(separator: ", "))")

        guard let downloadURL = URL(string: shard.download_url) else {
            throw ShardServiceError.invalidDownloadURL(shard.download_url)
        }
        let shardZipPath = try await fileClient.download(url: downloadURL)
        Logger.current.debug("Downloaded test products bundle.")

        let unzippedPath = try await fileSystem.makeTemporaryDirectory(prefix: "tuist-shard-unzip")
        _ = try await commandRunner
            .run(arguments: ["/usr/bin/ditto", "-x", "-k", shardZipPath.pathString, unzippedPath.pathString])
            .concatenatedString()

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
            reference: reference,
            shardPlanId: shard.shard_plan_id,
            testProductsPath: testProductsPath,
            modules: shard.modules,
            selectiveTestingGraph: selectiveTestingGraph
        )
    }

    /// Filters xctestrun plist data using raw PropertyListSerialization rather than Decodable because we need
    /// to preserve all fields (environment variables, test host paths, etc.) that aren't part of XCTestRun's typed model.
    func filterXCTestRun(
        plistData data: Data,
        modules: [String],
        suites: [String: [String]]
    ) throws -> Data {
        guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ShardServiceError.invalidXCTestRun
        }

        let moduleSet = Set(modules)

        if var configurations = plist["TestConfigurations"] as? [[String: Any]] {
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
        } else {
            for key in plist.keys where !key.hasPrefix("__") {
                guard let entry = plist[key] as? [String: Any],
                      let name = entry["BlueprintName"] as? String
                else { continue }

                if !moduleSet.contains(name) {
                    plist.removeValue(forKey: key)
                } else if !suites.isEmpty, let suiteNames = suites[name] {
                    var entry = entry
                    entry["OnlyTestIdentifiers"] = suiteNames
                    plist[key] = entry
                }
            }
        }

        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
