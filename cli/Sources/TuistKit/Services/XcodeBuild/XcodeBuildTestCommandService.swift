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

    init(
        fileSystem: FileSysteming = FileSystem(),
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        configLoader: ConfigLoading = ConfigLoader(),
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider(),
        uniqueIDGenerator: UniqueIDGenerating = UniqueIDGenerator(),
        xcodeBuildArgumentParser: XcodeBuildArgumentParsing = XcodeBuildArgumentParser(),
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
        xcActivityLogController: XCActivityLogControlling = XCActivityLogController(),
        inspectResultBundleService: InspectResultBundleServicing = InspectResultBundleService()
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
    }

    func run(
        passthroughXcodebuildArguments: [String]
    ) async throws {
        var passthroughXcodebuildArguments = passthroughXcodebuildArguments
        try await passthroughXcodebuildArguments.append(
            contentsOf: resultBundlePathArguments(passthroughXcodebuildArguments: passthroughXcodebuildArguments)
        )

        let xcodeBuildArguments = try await xcodeBuildArgumentParser.parse(passthroughXcodebuildArguments)
        var derivedDataPath: AbsolutePath? = xcodeBuildArguments.derivedDataPath
        if derivedDataPath == nil {
            if let projectPath = try await projectPath(xcodeBuildArguments: xcodeBuildArguments) {
                derivedDataPath = try await derivedDataLocator.locate(for: projectPath)
            }
        }

        let path = try await path(passthroughXcodebuildArguments: passthroughXcodebuildArguments)
        let config = try await configLoader.loadConfig(path: path)
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
