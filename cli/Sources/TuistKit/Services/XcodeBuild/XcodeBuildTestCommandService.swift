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
    private let stressNewTestsService: StressNewTestsServicing

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
        uploadBuildRunService: UploadBuildRunServicing? = UploadBuildRunService(),
        stressNewTestsService: StressNewTestsServicing = StressNewTestsService()
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
        self.stressNewTestsService = stressNewTestsService
    }

    func run(
        passthroughXcodebuildArguments: [String],
        skipQuarantine: Bool = false,
        shardIndex: Int? = nil,
        shardReference: String? = nil,
        shardPlanId: String? = nil,
        shardArchivePath: AbsolutePath? = nil,
        mode: TestProcessingMode? = nil,
        stressNewTests: StressNewTestsMode? = nil
    ) async throws {
        // Read before Tuist appends the shard's own identifiers, and before the quarantine skips: a
        // shard also narrows what runs, but it is a selection Tuist made and is already recorded on
        // the shard plan, whereas this is what the caller asked for.
        let callerOnlyTestIdentifiers = Self.testIdentifiers(for: "-only-testing", in: passthroughXcodebuildArguments)
        let callerSkipTestIdentifiers = Self.testIdentifiers(for: "-skip-testing", in: passthroughXcodebuildArguments)
        var passthroughXcodebuildArguments = passthroughXcodebuildArguments
        let (
            resultBundlePathArgs,
            resolvedResultBundlePath
        ) = try await resolveResultBundlePath(passthroughXcodebuildArguments: passthroughXcodebuildArguments)
        passthroughXcodebuildArguments.append(contentsOf: resultBundlePathArgs)

        let path = try await path(passthroughXcodebuildArguments: passthroughXcodebuildArguments)
        let config = try await configLoader.loadConfig(path: path)
        let mode = mode ?? TestProcessingMode.default(for: config.url)

        var resolvedShardPlanId: String?
        var shardTestProductsPath: AbsolutePath?
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
                reference: shardReference,
                shardPlanId: shardPlanId,
                testProductsPath: testProductsPath,
                testProductsArchivePath: shardArchivePath
            )
            resolvedShardPlanId = shard.shardPlanId

            passthroughXcodebuildArguments = removeOption("-workspace", from: passthroughXcodebuildArguments)
            passthroughXcodebuildArguments = removeOption("-scheme", from: passthroughXcodebuildArguments)
            passthroughXcodebuildArguments = removeOption("-project", from: passthroughXcodebuildArguments)

            // Downloaded or extracted products need an explicit `-testProductsPath` (and get cleaned up
            // afterwards); user-provided local products are already referenced via the passed-through
            // `-testProductsPath` and are left in place.
            if testProductsPath == nil {
                shardTestProductsPath = shard.testProductsPath
                passthroughXcodebuildArguments += ["-testProductsPath", shard.testProductsPath.pathString]
            }

            // Selection is delegated to `-only-testing` because xctestrun-level `OnlyTestIdentifiers`
            // does not filter Swift Testing tests.
            passthroughXcodebuildArguments += shard.testIdentifiers.flatMap { ["-only-testing", $0] }
            // The catch-all shard carries no `-only-testing` and instead skips every suite assigned to
            // other shards, so it runs whatever was not explicitly assigned (newly added or un-enumerated
            // suites) rather than dropping it.
            passthroughXcodebuildArguments += shard.skipTestIdentifiers.flatMap { ["-skip-testing", $0] }
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
        let parseSummary = mode == .local || stressNewTests != nil

        // The stress pass reruns only the candidates against the products the first pass built, in a
        // fresh process per repetition, so the caller's action, selection and repetition options are
        // replaced while everything else passes through.
        let stressPass: StressNewTestsPass = { identifiers, repetitions, stressResultBundlePath in
            try await xcodeBuildController.run(
                arguments: Self.stressPassArguments(
                    from: passthroughXcodebuildArguments,
                    identifiers: identifiers,
                    repetitions: repetitions,
                    resultBundlePath: stressResultBundlePath
                )
            )
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
            if parseSummary, let resultBundlePath {
                let rootDirectory = await rootDirectory()
                if let parsed = try await xcResultService.parse(path: resultBundlePath, rootDirectory: rootDirectory) {
                    testSummary = testQuarantineService.markQuarantinedTests(
                        testSummary: parsed,
                        quarantinedTests: mutedTests
                    )
                }
            }

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

            let stressResult = await stressNewTestsIfNeeded(
                mode: stressNewTests,
                summary: testSummary,
                firstPassFailed: !quarantinePass,
                config: config,
                mutedTests: mutedTests,
                stressPass: stressPass
            )

            await uploadResultBundleIfNeeded(
                testSummary: mode == .local ? testSummary : nil,
                resultBundlePath: resultBundlePath,
                projectDerivedDataDirectory: derivedDataPath,
                config: config,
                quarantinedTests: allQuarantinedTests,
                shardPlanId: resolvedShardPlanId,
                shardIndex: shardIndex,
                scheme: passedValue(for: "-scheme", arguments: passthroughXcodebuildArguments),
                mode: mode,
                onlyTestIdentifiers: callerOnlyTestIdentifiers,
                skipTestIdentifiers: callerSkipTestIdentifiers,
                stressNewTests: stressResult
            )

            if quarantinePass {
                if let shardTestProductsPath {
                    try? await fileSystem.remove(shardTestProductsPath)
                }
                if let stressResult, stressResult.blocks {
                    throw StressNewTestsError.blocked(stressResult.blockingCandidates)
                }
                return
            }

            try? await cleanUpShardArtifacts(testProductsPath: shardTestProductsPath)
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
        if parseSummary, let resultBundlePath {
            let rootDirectory = await rootDirectory()
            if let parsed = try await xcResultService.parse(path: resultBundlePath, rootDirectory: rootDirectory) {
                testSummary = testQuarantineService.markQuarantinedTests(
                    testSummary: parsed,
                    quarantinedTests: mutedTests
                )
            }
        }
        let stressResult = await stressNewTestsIfNeeded(
            mode: stressNewTests,
            summary: testSummary,
            firstPassFailed: testSummary == nil,
            config: config,
            mutedTests: mutedTests,
            stressPass: stressPass
        )
        await uploadResultBundleIfNeeded(
            testSummary: mode == .local ? testSummary : nil,
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: derivedDataPath,
            config: config,
            quarantinedTests: allQuarantinedTests,
            shardPlanId: resolvedShardPlanId,
            shardIndex: shardIndex,
            scheme: passedValue(for: "-scheme", arguments: passthroughXcodebuildArguments),
            mode: mode,
            onlyTestIdentifiers: callerOnlyTestIdentifiers,
            skipTestIdentifiers: callerSkipTestIdentifiers,
            stressNewTests: stressResult
        )
        if let shardTestProductsPath {
            try? await fileSystem.remove(shardTestProductsPath)
        }
        if let stressResult, stressResult.blocks {
            throw StressNewTestsError.blocked(stressResult.blockingCandidates)
        }
    }

    private func cleanUpShardArtifacts(testProductsPath: AbsolutePath?) async {
        if let testProductsPath {
            try? await fileSystem.remove(testProductsPath)
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

    private func rootDirectory() async -> AbsolutePath? {
        guard let workingDirectory = try? await Environment.current.currentWorkingDirectory() else {
            return nil
        }
        return try? await rootDirectoryLocator.locate(from: workingDirectory)
    }
}

/// The stress gate's own plumbing, kept out of the service's body: it is a
/// self-contained concern, and an extension keeps the type readable.
extension XcodeBuildTestCommandService {
    private func stressNewTestsIfNeeded(
        mode: StressNewTestsMode?,
        summary: TestSummary?,
        firstPassFailed: Bool,
        config: Tuist,
        mutedTests: [TestIdentifier],
        stressPass: @escaping StressNewTestsPass
    ) async -> StressNewTestsResult? {
        guard let mode, let fullHandle = config.fullHandle,
              let serverURL = try? serverEnvironmentService.url(configServerURL: config.url)
        else { return nil }
        return await stressNewTestsService.run(
            mode: mode,
            testSummary: summary,
            firstPassFailed: firstPassFailed,
            fullHandle: fullHandle,
            serverURL: serverURL,
            mutedTests: mutedTests,
            stressPass: stressPass
        )
    }

    private static let stressValueOptions: Set<String> = [
        "-resultBundlePath",
        "-test-iterations",
        "-test-repetition-relaunch-enabled",
        "-only-testing",
        "-skip-testing",
    ]

    private static let stressFlagOptions: Set<String> = [
        "-retry-tests-on-failure",
        "-run-tests-until-failure",
    ]

    /// The xcodebuild invocation for one stress group: the caller's arguments with the action swapped
    /// for `test-without-building`, their selection and repetition options dropped, and the group's
    /// identifiers, repetition count and result bundle appended.
    static func stressPassArguments(
        from arguments: [String],
        identifiers: [TestIdentifier],
        repetitions: Int,
        resultBundlePath: AbsolutePath
    ) -> [String] {
        var result: [String] = []
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == "test" || argument == "test-without-building", result.isEmpty {
                result.append("test-without-building")
                continue
            }
            if stressValueOptions.contains(argument) {
                _ = iterator.next()
                continue
            }
            if stressFlagOptions.contains(argument) {
                continue
            }
            if stressValueOptions.contains(where: { argument.hasPrefix("\($0):") }) {
                continue
            }
            result.append(argument)
        }
        result += identifiers.flatMap { ["-only-testing", $0.description] }
        result += [
            "-test-iterations", "\(repetitions)",
            "-test-repetition-relaunch-enabled", "YES",
            "-resultBundlePath", resultBundlePath.pathString,
        ]
        return result
    }
}

extension XcodeBuildTestCommandService {
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

    /// The identifiers the given option selects. xcodebuild accepts both `-only-testing ID` and
    /// `-only-testing:ID`.
    static func testIdentifiers(for option: String, in arguments: [String]) -> [String] {
        var identifiers: [String] = []
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == option, let identifier = iterator.next() {
                identifiers.append(identifier)
            } else if argument.hasPrefix("\(option):") {
                identifiers.append(String(argument.dropFirst(option.count + 1)))
            }
        }
        return identifiers
    }

    private func uploadResultBundleIfNeeded(
        testSummary: TestSummary?,
        resultBundlePath: AbsolutePath?,
        projectDerivedDataDirectory: AbsolutePath?,
        config: Tuist,
        quarantinedTests: [TestIdentifier] = [],
        shardPlanId: String? = nil,
        shardIndex: Int? = nil,
        scheme: String? = nil,
        mode: TestProcessingMode = .local,
        onlyTestIdentifiers: [String] = [],
        skipTestIdentifiers: [String] = [],
        stressNewTests: StressNewTestsResult? = nil
    ) async {
        guard config.fullHandle != nil else { return }

        await captureTestRunReport(scheme: scheme, resultBundlePath: resultBundlePath)

        do {
            switch mode {
            case .local:
                guard let testSummary else { return }
                _ = try await uploadResultBundleService.uploadTestSummary(
                    testSummary: testSummary,
                    projectDerivedDataDirectory: projectDerivedDataDirectory,
                    config: config,
                    shardPlanId: shardPlanId,
                    shardIndex: shardIndex,
                    onlyTestIdentifiers: onlyTestIdentifiers,
                    skipTestIdentifiers: skipTestIdentifiers,
                    stressNewTests: stressNewTests?.serverPayload
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
                    shardIndex: shardIndex,
                    onlyTestIdentifiers: onlyTestIdentifiers,
                    skipTestIdentifiers: skipTestIdentifiers,
                    stressNewTests: stressNewTests?.serverPayload
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

    /// Captures a lightweight per-scheme test summary into `RunMetadataStorage` so the GitHub Actions
    /// job summary can be rendered locally, without waiting for the server to finish parsing the
    /// uploaded result bundle. Best-effort: any failure is ignored.
    private func captureTestRunReport(scheme: String?, resultBundlePath: AbsolutePath?) async {
        guard let scheme, let resultBundlePath,
              let statuses = try? await xcResultService.parseTestStatuses(path: resultBundlePath)
        else { return }

        await RunMetadataStorage.current.add(
            testRunReport: RunReportTestRun(scheme: scheme, testStatuses: statuses)
        )
    }

    private func loadQuarantinedTests(
        config: Tuist,
        skipQuarantine: Bool
    ) async throws -> (muted: [TestIdentifier], skipped: [TestIdentifier]) {
        guard !skipQuarantine, let fullHandle = config.fullHandle else {
            return ([], [])
        }
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        async let mutedTask = testCaseListService.listAllTestCases(
            fullHandle: fullHandle, serverURL: serverURL, state: .muted
        )
        async let skippedTask = testCaseListService.listAllTestCases(
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
