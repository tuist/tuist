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
import TuistXcodeBuildProducts
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
    private let testCaseListService: TestCaseListServicing
    private let shardService: ShardServicing
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
        uploadResultBundleService: UploadResultBundleServicing = UploadResultBundleService(),
        xcResultService: XCResultServicing = XCResultService(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        testQuarantineService: TestQuarantineServicing = TestQuarantineService(),
        testCaseListService: TestCaseListServicing = TestCaseListService(),
        shardService: ShardServicing = ShardService(),
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
        self.uploadResultBundleService = uploadResultBundleService
        self.xcResultService = xcResultService
        self.rootDirectoryLocator = rootDirectoryLocator
        self.testQuarantineService = testQuarantineService
        self.testCaseListService = testCaseListService
        self.shardService = shardService
        self.serverEnvironmentService = serverEnvironmentService
        self.uploadBuildRunService = uploadBuildRunService
    }

    func run(
        passthroughXcodebuildArguments: [String],
        skipQuarantine: Bool = false,
        shardIndex: Int? = nil,
        shardArchivePath: AbsolutePath? = nil,
        mode: TestProcessingMode? = nil
    ) async throws {
        var passthroughXcodebuildArguments = passthroughXcodebuildArguments
        let (
            resultBundlePathArgs,
            resolvedResultBundlePath
        ) = try await resolveResultBundlePath(passthroughXcodebuildArguments: passthroughXcodebuildArguments)
        passthroughXcodebuildArguments.append(contentsOf: resultBundlePathArgs)

        let path = try await path(passthroughXcodebuildArguments: passthroughXcodebuildArguments)
        let config = try await configLoader.loadConfig(path: path)
        let mode = mode ?? TestProcessingMode.default(for: config.url)

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
                testProductsPath: testProductsPath,
                testProductsArchivePath: shardArchivePath
            )
            shardPlanId = shard.shardPlanId

            passthroughXcodebuildArguments = removeOption("-workspace", from: passthroughXcodebuildArguments)
            passthroughXcodebuildArguments = removeOption("-scheme", from: passthroughXcodebuildArguments)
            passthroughXcodebuildArguments = removeOption("-project", from: passthroughXcodebuildArguments)

            if let xcTestRunPath = shard.xcTestRunPath {
                shardXCTestRunPath = xcTestRunPath
                passthroughXcodebuildArguments = removeOption("-testProductsPath", from: passthroughXcodebuildArguments)
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

        let resultBundlePath: AbsolutePath? = resolvedResultBundlePath
        let (mutedTests, skippedTests) = try await loadQuarantinedTests(config: config, skipQuarantine: skipQuarantine)
        let allQuarantinedTests = mutedTests + skippedTests
        let xcodeBuildArgumentsWithSkip = passthroughXcodebuildArguments + skippedTests.flatMap { skipped in
            ["-skip-testing", skipped.description]
        }

        do {
            try await xcodeBuildController.run(arguments: xcodeBuildArgumentsWithSkip)
        } catch {
            if let derivedDataPath {
                await processBuildRun(
                    projectDerivedDataDirectory: derivedDataPath,
                    projectPath: path,
                    config: config,
                    passthroughXcodebuildArguments: passthroughXcodebuildArguments
                )
            }

            var testSummary: TestSummary?
            if mode == .local, let resultBundlePath {
                let rootDirectory = await rootDirectory()
                if let parsed = try await xcResultService.parse(path: resultBundlePath, rootDirectory: rootDirectory) {
                    testSummary = testQuarantineService.markQuarantinedTests(
                        testSummary: parsed,
                        quarantinedTests: mutedTests
                    )
                }
            }

            await uploadResultBundleIfNeeded(
                testSummary: testSummary,
                resultBundlePath: resultBundlePath,
                projectDerivedDataDirectory: derivedDataPath,
                config: config,
                quarantinedTests: allQuarantinedTests,
                shardPlanId: shardPlanId,
                shardIndex: shardIndex,
                mode: mode
            )

            let quarantinePass: Bool
            if let testSummary {
                quarantinePass = testQuarantineService.onlyQuarantinedTestsFailed(testSummary: testSummary)
            } else if let resultBundlePath {
                let testStatuses = try await xcResultService.parseTestStatuses(path: resultBundlePath)
                quarantinePass = testQuarantineService.onlyQuarantinedTestsFailed(
                    testStatuses: testStatuses,
                    quarantinedTests: mutedTests
                )
            } else {
                quarantinePass = false
            }

            if quarantinePass {
                if let shardTestProductsPath {
                    try? await fileSystem.remove(shardTestProductsPath)
                }
                if let shardXCTestRunPath {
                    try? await fileSystem.remove(shardXCTestRunPath)
                }
                return
            }

            try? await cleanUpShardArtifacts(testProductsPath: shardTestProductsPath, xcTestRunPath: shardXCTestRunPath)
            throw error
        }

        if let derivedDataPath {
            await processBuildRun(
                projectDerivedDataDirectory: derivedDataPath,
                projectPath: path,
                config: config,
                passthroughXcodebuildArguments: passthroughXcodebuildArguments
            )
        }

        var testSummary: TestSummary?
        if mode == .local, let resultBundlePath {
            let rootDirectory = await rootDirectory()
            if let parsed = try await xcResultService.parse(path: resultBundlePath, rootDirectory: rootDirectory) {
                testSummary = testQuarantineService.markQuarantinedTests(
                    testSummary: parsed,
                    quarantinedTests: mutedTests
                )
            }
        }
        await uploadResultBundleIfNeeded(
            testSummary: testSummary,
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: derivedDataPath,
            config: config,
            quarantinedTests: allQuarantinedTests,
            shardPlanId: shardPlanId,
            shardIndex: shardIndex,
            mode: mode
        )
        if let shardTestProductsPath {
            try? await fileSystem.remove(shardTestProductsPath)
        }
        if let shardXCTestRunPath {
            try? await fileSystem.remove(shardXCTestRunPath)
        }
    }

    private func cleanUpShardArtifacts(testProductsPath: AbsolutePath?, xcTestRunPath: AbsolutePath?) async {
        if let testProductsPath {
            try? await fileSystem.remove(testProductsPath)
        }
        if let xcTestRunPath {
            try? await fileSystem.remove(xcTestRunPath)
        }
    }

    private func processBuildRun(
        projectDerivedDataDirectory: AbsolutePath,
        projectPath: AbsolutePath,
        config: Tuist,
        passthroughXcodebuildArguments: [String]
    ) async {
        guard let mostRecentActivityLogPath = try? await xcActivityLogController.mostRecentActivityLogFile(
            projectDerivedDataDirectory: projectDerivedDataDirectory
        )
        else { return }

        await RunMetadataStorage.current.update(buildRunId: mostRecentActivityLogPath.path.basenameWithoutExt)

        guard let uploadBuildRunService, config.fullHandle != nil else { return }
        do {
            try await uploadBuildRunService.uploadBuildRun(
                activityLogPath: mostRecentActivityLogPath.path,
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

    private func resolveResultBundlePath(
        passthroughXcodebuildArguments: [String]
    ) async throws -> (additionalArguments: [String], resultBundlePath: AbsolutePath) {
        if let resultBundlePathString = passedValue(
            for: "-resultBundlePath",
            arguments: passthroughXcodebuildArguments
        ) {
            let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
            let resultBundlePath = try AbsolutePath(validating: resultBundlePathString, relativeTo: currentWorkingDirectory)
            return (additionalArguments: [], resultBundlePath: resultBundlePath)
        } else {
            let resultBundlePath = try cacheDirectoriesProvider
                .cacheDirectory(for: .runs)
                .appending(components: uniqueIDGenerator.uniqueID())
            return (
                additionalArguments: ["-resultBundlePath", resultBundlePath.pathString],
                resultBundlePath: resultBundlePath
            )
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
}

extension XcodeBuildTestCommandService {
    private func uploadResultBundleIfNeeded(
        testSummary: TestSummary?,
        resultBundlePath: AbsolutePath?,
        projectDerivedDataDirectory: AbsolutePath?,
        config: Tuist,
        quarantinedTests: [TestIdentifier] = [],
        shardPlanId: String? = nil,
        shardIndex: Int? = nil,
        mode: TestProcessingMode = .local
    ) async {
        guard config.fullHandle != nil else { return }

        do {
            switch mode {
            case .local:
                guard let testSummary else { return }
                _ = try await uploadResultBundleService.uploadTestSummary(
                    testSummary: testSummary,
                    projectDerivedDataDirectory: projectDerivedDataDirectory,
                    config: config,
                    shardPlanId: shardPlanId,
                    shardIndex: shardIndex
                )
            case .remote:
                guard let resultBundlePath else { return }
                let buildRunId = await RunMetadataStorage.current.buildRunId
                let test = try await uploadResultBundleService.uploadResultBundle(
                    resultBundlePath: resultBundlePath,
                    config: config,
                    quarantinedTests: quarantinedTests,
                    buildRunId: buildRunId,
                    shardPlanId: shardPlanId,
                    shardIndex: shardIndex
                )
                await RunMetadataStorage.current.update(testRunId: test.id)
                AlertController.current.success(
                    .alert("Result bundle uploaded for processing. View at \(test.url)")
                )
            case .off:
                return
            }
        } catch {
            AlertController.current.warning(.alert("Failed to upload test results: \(error.localizedDescription)"))
        }
    }

    private func loadQuarantinedTests(
        config: Tuist,
        skipQuarantine: Bool
    ) async throws -> (muted: [TestIdentifier], skipped: [TestIdentifier]) {
        guard !skipQuarantine, let fullHandle = config.fullHandle else {
            return ([], [])
        }
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        async let mutedTask = testCaseListService.listTestCases(
            fullHandle: fullHandle, serverURL: serverURL, state: .muted
        )
        async let skippedTask = testCaseListService.listTestCases(
            fullHandle: fullHandle, serverURL: serverURL, state: .skipped
        )
        do {
            let (muted, skipped) = try await (mutedTask, skippedTask)
            let total = muted.count + skipped.count
            if total > 0 {
                Logger.current.notice(
                    "Found \(total) quarantined test(s): \(muted.count) muted, \(skipped.count) skipped",
                    metadata: .subsection
                )
            }
            return (muted, skipped)
        } catch {
            AlertController.current.warning(
                .alert("Failed to fetch quarantined tests: \(error.localizedDescription). Running all tests.")
            )
            return ([], [])
        }
    }
}
