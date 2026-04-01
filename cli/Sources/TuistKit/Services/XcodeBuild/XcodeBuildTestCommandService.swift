import FileSystem
import Foundation
import Path
import TuistAlert
import TuistAutomation
import TuistCI
import TuistConfig
import TuistConfigLoader
import TuistCore
import TuistEnvironment
import TuistLoader
import TuistLogging
import TuistRootDirectoryLocator
import TuistServer
import TuistSupport
import TuistUniqueIDGenerator
import TuistXCActivityLog
import TuistXCResultService
import XCResultParser

struct XcodeBuildTestCommandService {
    private let fileSystem: FileSysteming
    private let xcodeBuildController: XcodeBuildControlling
    private let configLoader: ConfigLoading
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let uniqueIDGenerator: UniqueIDGenerating
    private let xcodeBuildArgumentParser: XcodeBuildArgumentParsing
    private let derivedDataLocator: DerivedDataLocating
    private let xcActivityLogController: XCActivityLogControlling
    private let uploadResultBundleService: UploadResultBundleServicing
    private let xcResultService: XCResultServicing
    private let rootDirectoryLocator: RootDirectoryLocating
    private let testQuarantineService: TestQuarantineServicing
    private let shardService: ShardServicing
    private let serverEnvironmentService: ServerEnvironmentServicing

    init(
        fileSystem: FileSysteming = FileSystem(),
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        configLoader: ConfigLoading = ConfigLoader(),
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider(),
        uniqueIDGenerator: UniqueIDGenerating = UniqueIDGenerator(),
        xcodeBuildArgumentParser: XcodeBuildArgumentParsing = XcodeBuildArgumentParser(),
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
        xcActivityLogController: XCActivityLogControlling = XCActivityLogController(),
        uploadResultBundleService: UploadResultBundleServicing = UploadResultBundleService(),
        xcResultService: XCResultServicing = XCResultService(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        testQuarantineService: TestQuarantineServicing = TestQuarantineService(),
        shardService: ShardServicing = ShardService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService()
    ) {
        self.fileSystem = fileSystem
        self.xcodeBuildController = xcodeBuildController
        self.configLoader = configLoader
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.uniqueIDGenerator = uniqueIDGenerator
        self.xcodeBuildArgumentParser = xcodeBuildArgumentParser
        self.derivedDataLocator = derivedDataLocator
        self.xcActivityLogController = xcActivityLogController
        self.uploadResultBundleService = uploadResultBundleService
        self.xcResultService = xcResultService
        self.rootDirectoryLocator = rootDirectoryLocator
        self.testQuarantineService = testQuarantineService
        self.shardService = shardService
        self.serverEnvironmentService = serverEnvironmentService
    }

    func run(
        passthroughXcodebuildArguments: [String],
        skipQuarantine: Bool = false,
        shardIndex: Int? = nil
    ) async throws {
        var passthroughXcodebuildArguments = passthroughXcodebuildArguments
        try await passthroughXcodebuildArguments.append(
            contentsOf: resultBundlePathArguments(passthroughXcodebuildArguments: passthroughXcodebuildArguments)
        )

        let path = try await path(passthroughXcodebuildArguments: passthroughXcodebuildArguments)
        let config = try await configLoader.loadConfig(path: path)

        var shardPlanId: String?
        var shardTestProductsPath: AbsolutePath?
        var shardXCTestRunPath: AbsolutePath?
        if let shardIndex, let fullHandle = config.fullHandle {
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

            let testProductsPath: AbsolutePath?
            if let localPathString = passedValue(for: "-testProductsPath", arguments: passthroughXcodebuildArguments) {
                let currentDirectory = try await Environment.current.currentWorkingDirectory()
                testProductsPath = try AbsolutePath(validating: localPathString, relativeTo: currentDirectory)
            } else {
                testProductsPath = nil
            }

            let shard = try await shardService.shard(
                shardIndex: shardIndex,
                fullHandle: fullHandle,
                serverURL: serverURL,
                testProductsPath: testProductsPath
            )
            shardPlanId = shard.shardPlanId

            passthroughXcodebuildArguments = removeOption("-workspace", from: passthroughXcodebuildArguments)
            passthroughXcodebuildArguments = removeOption("-scheme", from: passthroughXcodebuildArguments)
            passthroughXcodebuildArguments = removeOption("-project", from: passthroughXcodebuildArguments)

            if let xcTestRunPath = shard.xcTestRunPath {
                shardXCTestRunPath = xcTestRunPath
                passthroughXcodebuildArguments = removeOption("-xctestrun", from: passthroughXcodebuildArguments)
                passthroughXcodebuildArguments += ["-xctestrun", xcTestRunPath.pathString]
            } else {
                shardTestProductsPath = shard.testProductsPath
                passthroughXcodebuildArguments += ["-testProductsPath", shard.testProductsPath.pathString]
            }
        }

        let xcodeBuildArguments = try await xcodeBuildArgumentParser.parse(passthroughXcodebuildArguments)
        var derivedDataPath: AbsolutePath? = xcodeBuildArguments.derivedDataPath
        if derivedDataPath == nil {
            if let projectPath = try await projectPath(xcodeBuildArguments: xcodeBuildArguments) {
                derivedDataPath = try await derivedDataLocator.locate(for: projectPath)
            }
        }

        let resultBundlePath = await RunMetadataStorage.current.resultBundlePath

        let quarantinedTests = await testQuarantineService.quarantinedTests(config: config, skipQuarantine: skipQuarantine)

        do {
            try await xcodeBuildController.run(arguments: passthroughXcodebuildArguments)
        } catch {
            if let derivedDataPath {
                await updateBuildRunId(projectDerivedDataDirectory: derivedDataPath)
            }

            let rootDirectory = await rootDirectory()
            var testSummary: TestSummary?
            if let resultBundlePath,
               let parsed = try await xcResultService.parse(path: resultBundlePath, rootDirectory: rootDirectory)
            {
                testSummary = testQuarantineService.markQuarantinedTests(testSummary: parsed, quarantinedTests: quarantinedTests)
            }

            await uploadResultBundleIfNeeded(
                testSummary: testSummary,
                projectDerivedDataDirectory: derivedDataPath,
                config: config,
                shardPlanId: shardPlanId,
                shardIndex: shardIndex
            )

            if let testSummary, testQuarantineService.onlyQuarantinedTestsFailed(testSummary: testSummary) {
                if let shardTestProductsPath {
                    try? await fileSystem.remove(shardTestProductsPath)
                }
                if let shardXCTestRunPath {
                    try? await fileSystem.remove(shardXCTestRunPath)
                }
                return
            }

            if let shardTestProductsPath {
                try? await fileSystem.remove(shardTestProductsPath)
            }
            if let shardXCTestRunPath {
                try? await fileSystem.remove(shardXCTestRunPath)
            }
            throw error
        }

        if let derivedDataPath {
            await updateBuildRunId(projectDerivedDataDirectory: derivedDataPath)
        }

        let rootDirectory = await rootDirectory()
        var testSummary: TestSummary?
        if let resultBundlePath,
           let parsed = try await xcResultService.parse(path: resultBundlePath, rootDirectory: rootDirectory)
        {
            testSummary = testQuarantineService.markQuarantinedTests(testSummary: parsed, quarantinedTests: quarantinedTests)
        }
        await uploadResultBundleIfNeeded(
            testSummary: testSummary,
            projectDerivedDataDirectory: derivedDataPath,
            config: config,
            shardPlanId: shardPlanId,
            shardIndex: shardIndex
        )
        if let shardTestProductsPath {
            try? await fileSystem.remove(shardTestProductsPath)
        }
        if let shardXCTestRunPath {
            try? await fileSystem.remove(shardXCTestRunPath)
        }
    }

    private func updateBuildRunId(projectDerivedDataDirectory: AbsolutePath) async {
        guard let mostRecentActivityLogPath = try? await xcActivityLogController.mostRecentActivityLogFile(
            projectDerivedDataDirectory: projectDerivedDataDirectory
        )
        else { return }

        await RunMetadataStorage.current.update(buildRunId: mostRecentActivityLogPath.path.basenameWithoutExt)
    }

    private func projectPath(xcodeBuildArguments: XcodeBuildArguments) async throws -> AbsolutePath? {
        let currentDirectory = try await Environment.current.currentWorkingDirectory()
        if let workspacePath = xcodeBuildArguments.workspacePath {
            return workspacePath
        } else if let projectPath = xcodeBuildArguments.projectPath {
            return projectPath
        } else if let xcodeProjPath = try await fileSystem.glob(
            directory: currentDirectory,
            include: ["*.xcodeproj"]
        )
        .collect()
        .first {
            return xcodeProjPath
        } else if let workspacePath = try await fileSystem.glob(
            directory: currentDirectory,
            include: ["*.xcworkspace"]
        )
        .collect()
        .first {
            return workspacePath
        } else {
            return nil
        }
    }

    private func resultBundlePathArguments(
        passthroughXcodebuildArguments: [String]
    ) async throws -> [String] {
        if let resultBundlePathString = passedValue(
            for: "-resultBundlePath",
            arguments: passthroughXcodebuildArguments
        ) {
            let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
            let resultBundlePath = try AbsolutePath(validating: resultBundlePathString, relativeTo: currentWorkingDirectory)
            await RunMetadataStorage.current.update(
                resultBundlePath: resultBundlePath
            )
            return []
        } else {
            let resultBundlePath = try cacheDirectoriesProvider
                .cacheDirectory(for: .runs)
                .appending(components: uniqueIDGenerator.uniqueID())
            await RunMetadataStorage.current.update(
                resultBundlePath: resultBundlePath
            )
            return ["-resultBundlePath", resultBundlePath.pathString]
        }
    }

    private func path(
        passthroughXcodebuildArguments: [String]
    ) async throws -> AbsolutePath {
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        if let workspaceOrProjectPath = passedValue(for: "-workspace", arguments: passthroughXcodebuildArguments) ??
            passedValue(for: "-project", arguments: passthroughXcodebuildArguments)
        {
            return try AbsolutePath(validating: workspaceOrProjectPath, relativeTo: currentWorkingDirectory)
        } else {
            return currentWorkingDirectory
        }
    }

    private func passedValue(
        for option: String,
        arguments: [String]
    ) -> String? {
        guard let optionIndex = arguments.firstIndex(of: option) else { return nil }
        let valueIndex = arguments.index(after: optionIndex)
        guard arguments.endIndex > valueIndex else { return nil }
        return arguments[valueIndex]
    }

    private func removeOption(_ option: String, from arguments: [String]) -> [String] {
        guard let index = arguments.firstIndex(of: option) else { return arguments }
        var result = arguments
        result.remove(at: index)
        if result.indices.contains(index) {
            result.remove(at: index)
        }
        return result
    }

    private func rootDirectory() async -> AbsolutePath? {
        guard let workingDirectory = try? await Environment.current.currentWorkingDirectory() else {
            return nil
        }
        return try? await rootDirectoryLocator.locate(from: workingDirectory)
    }

    private func uploadResultBundleIfNeeded(
        testSummary: TestSummary?,
        projectDerivedDataDirectory: AbsolutePath?,
        config: Tuist,
        shardPlanId: String? = nil,
        shardIndex: Int? = nil
    ) async {
        guard let testSummary,
              config.fullHandle != nil
        else { return }

        do {
            _ = try await uploadResultBundleService.uploadResultBundle(
                testSummary: testSummary,
                projectDerivedDataDirectory: projectDerivedDataDirectory,
                config: config,
                shardPlanId: shardPlanId,
                shardIndex: shardIndex
            )
        } catch {
            AlertController.current.warning(.alert("Failed to upload test results: \(error.localizedDescription)"))
        }
    }
}
