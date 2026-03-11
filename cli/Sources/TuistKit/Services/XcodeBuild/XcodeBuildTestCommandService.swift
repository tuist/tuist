import FileSystem
import Foundation
import Path
import TuistAlert
import TuistAutomation
import TuistConfig
import TuistConfigLoader
import TuistCore
import TuistEnvironment
import TuistLoader
import TuistLogging
import TuistServer
import TuistSupport
import TuistUniqueIDGenerator
import TuistXCActivityLog

struct XcodeBuildTestCommandService {
    private let fileSystem: FileSysteming
    private let xcodeBuildController: XcodeBuildControlling
    private let configLoader: ConfigLoading
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let uniqueIDGenerator: UniqueIDGenerating
    private let xcodeBuildArgumentParser: XcodeBuildArgumentParsing
    private let derivedDataLocator: DerivedDataLocating
    private let xcActivityLogController: XCActivityLogControlling
    private let inspectResultBundleService: InspectResultBundleServicing
    private let shardExecuteService: ShardExecuteServicing
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
        inspectResultBundleService: InspectResultBundleServicing = InspectResultBundleService(),
        shardExecuteService: ShardExecuteServicing = ShardExecuteService(),
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
        self.inspectResultBundleService = inspectResultBundleService
        self.shardExecuteService = shardExecuteService
        self.serverEnvironmentService = serverEnvironmentService
    }

    func run(
        passthroughXcodebuildArguments: [String],
        shardConfiguration: ShardConfiguration? = nil,
        shardIndex: Int? = nil
    ) async throws {
        var passthroughXcodebuildArguments = passthroughXcodebuildArguments
        try await passthroughXcodebuildArguments.append(
            contentsOf: resultBundlePathArguments(passthroughXcodebuildArguments: passthroughXcodebuildArguments)
        )

        let path = try await path(passthroughXcodebuildArguments: passthroughXcodebuildArguments)
        let config = try await configLoader.loadConfig(path: path)

        if let shardIndex, let fullHandle = config.fullHandle {
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
            let schemeName = passedValue(for: "-scheme", arguments: passthroughXcodebuildArguments) ?? "Test"
            let currentDir = try await Environment.current.currentWorkingDirectory()
            let outputPath = currentDir.appending(components: ".tuist", "shard-output")
            try await fileSystem.makeDirectory(at: outputPath)
            let result = try await shardExecuteService.execute(
                shardIndex: shardIndex,
                scheme: schemeName,
                fullHandle: fullHandle,
                serverURL: serverURL,
                outputPath: outputPath
            )
            passthroughXcodebuildArguments = removeOption("-project", from: passthroughXcodebuildArguments)
            passthroughXcodebuildArguments = removeOption("-workspace", from: passthroughXcodebuildArguments)
            passthroughXcodebuildArguments = removeOption("-scheme", from: passthroughXcodebuildArguments)
            passthroughXcodebuildArguments += ["-testProductsPath", result.testProductsPath.pathString]
            for target in result.testTargets {
                passthroughXcodebuildArguments += ["-only-testing", target]
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

        do {
            try await xcodeBuildController.run(arguments: passthroughXcodebuildArguments)
        } catch {
            if let derivedDataPath {
                await updateBuildRunId(projectDerivedDataDirectory: derivedDataPath)
            }
            await inspectResultBundleIfNeeded(
                resultBundlePath: resultBundlePath,
                projectDerivedDataDirectory: derivedDataPath,
                config: config
            )
            throw error
        }

        if let derivedDataPath {
            await updateBuildRunId(projectDerivedDataDirectory: derivedDataPath)
        }
        await inspectResultBundleIfNeeded(
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: derivedDataPath,
            config: config
        )
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

    private func removeOption(
        _ option: String,
        from arguments: [String]
    ) -> [String] {
        var result = arguments
        if let index = result.firstIndex(of: option) {
            result.remove(at: index)
            if index < result.count {
                result.remove(at: index)
            }
        }
        return result
    }

    private func inspectResultBundleIfNeeded(
        resultBundlePath: AbsolutePath?,
        projectDerivedDataDirectory: AbsolutePath?,
        config: Tuist
    ) async {
        guard let resultBundlePath,
              let projectDerivedDataDirectory,
              config.fullHandle != nil,
              (try? await fileSystem.exists(resultBundlePath)) == true
        else { return }

        do {
            _ = try await inspectResultBundleService.inspectResultBundle(
                resultBundlePath: resultBundlePath,
                projectDerivedDataDirectory: projectDerivedDataDirectory,
                config: config
            )
        } catch {
            AlertController.current.warning(.alert("Failed to upload test results: \(error.localizedDescription)"))
        }
    }
}
