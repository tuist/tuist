import FileSystem
import Foundation
import Path
import TuistAlert
import TuistAutomation
import TuistConfigLoader
import TuistCore
import TuistEnvironment
import TuistLoader
import TuistLogging
import TuistServer
import TuistSupport
import TuistUniqueIDGenerator
import TuistXCActivityLog

struct XcodeBuildBuildCommandService {
    private let fileSystem: FileSysteming
    private let xcodeBuildController: XcodeBuildControlling
    private let configLoader: ConfigLoading
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let uniqueIDGenerator: UniqueIDGenerating
    private let xcodeBuildArgumentParser: XcodeBuildArgumentParsing
    private let derivedDataLocator: DerivedDataLocating
    private let xcActivityLogController: XCActivityLogControlling
    private let shardPlanService: ShardPlanServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let uploadBuildRunService: UploadBuildRunServicing?

    init(
        fileSystem: FileSysteming = FileSystem(),
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        configLoader: ConfigLoading = ConfigLoader(),
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider(),
        uniqueIDGenerator: UniqueIDGenerating = UniqueIDGenerator(),
        xcodeBuildArgumentParser: XcodeBuildArgumentParsing = XcodeBuildArgumentParser(),
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
        xcActivityLogController: XCActivityLogControlling = XCActivityLogController(),
        shardPlanService: ShardPlanServicing = ShardPlanService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        uploadBuildRunService: UploadBuildRunServicing? = UploadBuildRunService()
    ) {
        self.fileSystem = fileSystem
        self.xcodeBuildController = xcodeBuildController
        self.configLoader = configLoader
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.uniqueIDGenerator = uniqueIDGenerator
        self.xcodeBuildArgumentParser = xcodeBuildArgumentParser
        self.derivedDataLocator = derivedDataLocator
        self.xcActivityLogController = xcActivityLogController
        self.shardPlanService = shardPlanService
        self.serverEnvironmentService = serverEnvironmentService
        self.uploadBuildRunService = uploadBuildRunService
    }

    func run(
        passthroughXcodebuildArguments: [String],
        shardReference: String? = nil,
        shardGranularity: ShardGranularity = .module,
        shardMin: Int? = nil,
        shardMax: Int? = nil,
        shardTotal: Int? = nil,
        shardMaxDuration: Int? = nil,
        shardSkipUpload: Bool = false,
        shardArchivePath: AbsolutePath? = nil
    ) async throws {
        var passthroughXcodebuildArguments = passthroughXcodebuildArguments
        try await passthroughXcodebuildArguments.append(
            contentsOf: resultBundlePathArguments(passthroughXcodebuildArguments: passthroughXcodebuildArguments)
        )

        // When sharding, ensure -testProductsPath is set so xcodebuild produces
        // a .xctestproducts bundle (required for shard distribution).
        let isSharding = shardMin != nil || shardMax != nil || shardTotal != nil
        let schemeName = passedValue(for: "-scheme", arguments: passthroughXcodebuildArguments)
        if isSharding {
            guard let schemeName else {
                throw XcodeBuildBuildCommandServiceError.schemeRequired
            }
            if passedValue(for: "-testProductsPath", arguments: passthroughXcodebuildArguments) == nil {
                let testProductsDir = try await fileSystem.makeTemporaryDirectory(prefix: "shard-test-products")
                let productsPath = testProductsDir.appending(component: "\(schemeName).xctestproducts")
                passthroughXcodebuildArguments += ["-testProductsPath", productsPath.pathString]
            }
        }

        try await xcodeBuildController.run(arguments: passthroughXcodebuildArguments)
        let xcodeBuildArguments = try await xcodeBuildArgumentParser.parse(passthroughXcodebuildArguments)
        var derivedDataPath: AbsolutePath? = xcodeBuildArguments.derivedDataPath
        if derivedDataPath == nil {
            guard let projectPath = try await projectPath(xcodeBuildArguments: xcodeBuildArguments) else { return }
            derivedDataPath = try await derivedDataLocator.locate(for: projectPath)
        }
        if let derivedDataPath,
           let mostRecentActivityLogFile = try await xcActivityLogController.mostRecentActivityLogFile(
               projectDerivedDataDirectory: derivedDataPath
           )
        {
            await RunMetadataStorage.current.update(buildRunId: mostRecentActivityLogFile.path.basenameWithoutExt)

            let buildPath = try await path(passthroughXcodebuildArguments: passthroughXcodebuildArguments)
            await uploadBuildRunIfNeeded(
                activityLogPath: mostRecentActivityLogFile.path,
                projectPath: buildPath,
                passthroughXcodebuildArguments: passthroughXcodebuildArguments
            )
        }

        if isSharding, let schemeName {
            let testProductsPath = try await resolveTestProductsPath(
                passthroughXcodebuildArguments: passthroughXcodebuildArguments,
                derivedDataPath: derivedDataPath
            )
            let buildPath = try await path(passthroughXcodebuildArguments: passthroughXcodebuildArguments)
            let config = try await configLoader.loadConfig(path: buildPath)
            guard let fullHandle = config.fullHandle else {
                Logger.current.warning("Shard configuration provided but no project handle configured. Skipping shard plan.")
                return
            }
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
            let destination = passedValue(for: "-destination", arguments: passthroughXcodebuildArguments)
            let buildRunId = await RunMetadataStorage.current.buildRunId
            _ = try await shardPlanService.plan(
                xctestproductsPath: testProductsPath,
                destination: destination,
                reference: shardReference,
                shardGranularity: shardGranularity,
                shardMin: shardMin,
                shardMax: shardMax,
                shardTotal: shardTotal,
                shardMaxDuration: shardMaxDuration,
                fullHandle: fullHandle,
                serverURL: serverURL,
                buildRunId: buildRunId,
                skipUpload: shardSkipUpload,
                archivePath: shardArchivePath
            )
        }
    }

    private func uploadBuildRunIfNeeded(
        activityLogPath: AbsolutePath,
        projectPath: AbsolutePath,
        passthroughXcodebuildArguments: [String]
    ) async {
        guard let uploadBuildRunService else { return }
        do {
            let config = try await configLoader.loadConfig(path: projectPath)
            guard config.fullHandle != nil else { return }
            try await uploadBuildRunService.uploadBuildRun(
                activityLogPath: activityLogPath,
                projectPath: projectPath,
                config: config,
                scheme: passedValue(for: "-scheme", arguments: passthroughXcodebuildArguments),
                configuration: passedValue(for: "-configuration", arguments: passthroughXcodebuildArguments)
            )
        } catch {
            AlertController.current.warning(.alert("Failed to upload build: \(error.localizedDescription)"))
        }
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

    private func resolveTestProductsPath(
        passthroughXcodebuildArguments: [String],
        derivedDataPath: AbsolutePath?
    ) async throws -> AbsolutePath {
        if let explicitPath = passedValue(for: "-testProductsPath", arguments: passthroughXcodebuildArguments) {
            let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
            return try AbsolutePath(validating: explicitPath, relativeTo: currentWorkingDirectory)
        }

        guard let derivedDataPath else {
            throw XcodeBuildBuildCommandServiceError.testProductsNotFound
        }

        let buildProductsPath = derivedDataPath.appending(components: "Build", "Products")
        let matches = try await fileSystem
            .glob(directory: buildProductsPath, include: ["*.xctestproducts"])
            .collect()

        let pathsWithDates = try await matches
            .concurrentCompactMap { path -> (path: AbsolutePath, date: Date)? in
                guard let metadata = try? await fileSystem.fileMetadata(at: path) else { return nil }
                return (path, metadata.lastModificationDate)
            }
        guard let match = pathsWithDates.sorted(by: { $0.date > $1.date }).first?.path else {
            throw XcodeBuildBuildCommandServiceError.testProductsNotFound
        }

        return match
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
}

enum XcodeBuildBuildCommandServiceError: LocalizedError {
    case testProductsNotFound
    case schemeRequired

    var errorDescription: String? {
        switch self {
        case .testProductsNotFound:
            return "Could not find .xctestproducts bundle. Pass -testProductsPath or -derivedDataPath explicitly."
        case .schemeRequired:
            return "The -scheme argument is required when sharding is enabled."
        }
    }
}
