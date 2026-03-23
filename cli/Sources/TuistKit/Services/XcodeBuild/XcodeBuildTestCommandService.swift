import FileSystem
import Foundation
import Path
import TuistAlert
import TuistAutomation
import TuistConfig
import TuistConfigLoader
import TuistCore
import TuistEnvironment
import TuistGit
import TuistLoader
import TuistLogging
import TuistServer
import TuistSupport
import TuistUniqueIDGenerator
import TuistXCActivityLog
import TuistXCResultService

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
    private let listTestCasesService: ListTestCasesServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let xcResultService: XCResultServicing
    private let gitController: GitControlling

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
        listTestCasesService: ListTestCasesServicing = ListTestCasesService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        xcResultService: XCResultServicing = XCResultService(),
        gitController: GitControlling = GitController()
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
        self.listTestCasesService = listTestCasesService
        self.serverEnvironmentService = serverEnvironmentService
        self.xcResultService = xcResultService
        self.gitController = gitController
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

        let quarantinedTests = await quarantinedTests(config: config)

        do {
            try await xcodeBuildController.run(arguments: passthroughXcodebuildArguments)
        } catch {
            if let derivedDataPath {
                await updateBuildRunId(projectDerivedDataDirectory: derivedDataPath)
            }

            let rootDirectory = await rootDirectory()
            var testSummary: TestSummary?
            if let resultBundlePath {
                testSummary = try await xcResultService.parse(path: resultBundlePath, rootDirectory: rootDirectory)
            }

            var onlyQuarantinedFailures = false
            if !quarantinedTests.isEmpty, let testSummary {
                let (quarantinedFailures, realFailures) = classifyFailures(
                    testSummary: testSummary,
                    quarantinedTests: quarantinedTests
                )
                if realFailures.isEmpty, !quarantinedFailures.isEmpty {
                    onlyQuarantinedFailures = true
                    let failureNames = quarantinedFailures.map { testCase in
                        [testCase.module, testCase.testSuite, testCase.name]
                            .compactMap { $0 }
                            .joined(separator: "/")
                    }.joined(separator: ", ")
                    Logger.current.notice(
                        "\(quarantinedFailures.count) quarantined test(s) failed (exit code overridden to 0): \(failureNames)",
                        metadata: .subsection
                    )
                } else if !realFailures.isEmpty, !quarantinedFailures.isEmpty {
                    Logger.current.notice(
                        "\(quarantinedFailures.count) quarantined test(s) failed, \(realFailures.count) non-quarantined test(s) failed",
                        metadata: .subsection
                    )
                }
            }

            await uploadResultBundleIfNeeded(
                testSummary: testSummary,
                projectDerivedDataDirectory: derivedDataPath,
                config: config
            )

            if onlyQuarantinedFailures {
                return
            }

            throw error
        }

        if let derivedDataPath {
            await updateBuildRunId(projectDerivedDataDirectory: derivedDataPath)
        }

        let rootDirectory = await rootDirectory()
        var testSummary: TestSummary?
        if let resultBundlePath {
            testSummary = try await xcResultService.parse(path: resultBundlePath, rootDirectory: rootDirectory)
        }
        await uploadResultBundleIfNeeded(
            testSummary: testSummary,
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

    private func quarantinedTests(config: Tuist) async -> [TestIdentifier] {
        guard let fullHandle = config.fullHandle else { return [] }
        do {
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
            let response = try await listTestCasesService.listTestCases(
                fullHandle: fullHandle,
                serverURL: serverURL,
                flaky: nil,
                quarantined: true,
                page: 1,
                pageSize: 500
            )
            let tests = try response.test_cases.map { testCase in
                try TestIdentifier(
                    target: testCase.module.name,
                    class: testCase.suite?.name,
                    method: testCase.name
                )
            }
            if !tests.isEmpty {
                Logger.current.notice(
                    "Found \(tests.count) quarantined test(s)",
                    metadata: .subsection
                )
            }
            return tests
        } catch {
            Logger.current.log(
                level: .warning,
                "Failed to fetch quarantined tests: \(error.localizedDescription). Running all tests."
            )
            return []
        }
    }

    private func classifyFailures(
        testSummary: TestSummary,
        quarantinedTests: [TestIdentifier]
    ) -> (quarantinedFailures: [TestCase], realFailures: [TestCase]) {
        let failedTestCases = testSummary.testCases.filter { $0.status == .failed }
        var quarantinedFailures: [TestCase] = []
        var realFailures: [TestCase] = []

        for testCase in failedTestCases {
            let isQuarantined = quarantinedTests.contains { quarantined in
                guard testCase.module == quarantined.target else { return false }
                if let quarantinedClass = quarantined.class,
                   testCase.testSuite != quarantinedClass
                {
                    return false
                }
                if let quarantinedMethod = quarantined.method,
                   testCase.name != quarantinedMethod
                {
                    return false
                }
                return true
            }
            if isQuarantined {
                quarantinedFailures.append(testCase)
            } else {
                realFailures.append(testCase)
            }
        }

        return (quarantinedFailures: quarantinedFailures, realFailures: realFailures)
    }

    private func rootDirectory() async -> AbsolutePath? {
        guard let currentWorkingDirectory = try? await Environment.current.currentWorkingDirectory() else {
            return nil
        }
        let workingDirectory = Environment.current.workspacePath ?? currentWorkingDirectory
        if gitController.isInGitRepository(workingDirectory: workingDirectory) {
            return try? gitController.topLevelGitDirectory(workingDirectory: workingDirectory)
        }
        return nil
    }

    private func uploadResultBundleIfNeeded(
        testSummary: TestSummary?,
        projectDerivedDataDirectory: AbsolutePath?,
        config: Tuist
    ) async {
        guard let testSummary,
              let projectDerivedDataDirectory,
              config.fullHandle != nil
        else { return }

        do {
            _ = try await uploadResultBundleService.uploadResultBundle(
                testSummary: testSummary,
                projectDerivedDataDirectory: projectDerivedDataDirectory,
                config: config
            )
        } catch {
            AlertController.current.warning(.alert("Failed to upload test results: \(error.localizedDescription)"))
        }
    }
}
