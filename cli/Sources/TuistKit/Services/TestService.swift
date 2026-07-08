import FileSystem
import Foundation
import Path
import struct TSCUtility.Version
import TuistAlert
import TuistAutomation
import TuistCI
import TuistConfig
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistGit
import TuistLoader
import TuistLogging
import TuistRootDirectoryLocator
import TuistServer
import TuistSupport
import TuistXCActivityLog
import TuistXcodeBuildProducts
import TuistXCResultService
import XcodeGraph
import XCResultParser

public enum TestServiceError: FatalError, Equatable {
    case schemeNotFound(scheme: String, existing: [String])
    case schemeWithoutTestableTargets(scheme: String, testPlan: String?)
    case testPlanNotFound(scheme: String, testPlan: String, existing: [String])
    case testIdentifierInvalid(value: String)
    case duplicatedTestTargets(Set<TestIdentifier>)
    case nothingToSkip(skipped: [TestIdentifier], included: [TestIdentifier])
    case actionInvalid
    case testProductsNotFound
    case unspecifiedPlatform(target: String, platforms: [String])
    case shardPlanningRequiresBuildOnly
    case shardIndexRequiresWithoutBuilding
    case shardingRequiresFullHandle

    // Error description

    public var description: String {
        switch self {
        case let .schemeNotFound(scheme, existing):
            return
                "Couldn't find scheme \(scheme). The available schemes are: \(existing.joined(separator: ", "))."
        case let .schemeWithoutTestableTargets(scheme, testPlan):
            let testPlanMessage: String
            if let testPlan, !testPlan.isEmpty {
                testPlanMessage = "test plan \(testPlan) in "
            } else {
                testPlanMessage = ""
            }
            return
                "The \(testPlanMessage)scheme \(scheme) cannot be built because it contains no buildable targets."
        case let .testPlanNotFound(scheme, testPlan, existing):
            let existingMessage: String
            if existing.isEmpty {
                existingMessage =
                    "We could not execute the test plan \(testPlan) because the scheme \(scheme) doesn't have test plans defined."
            } else {
                existingMessage =
                    "The test plan \(testPlan) in scheme \(scheme) doesn't exist. The following following test plans are defined: \(existing.joined(separator: ","))"
            }
            return "Couldn't find test plan \(testPlan) in scheme \(scheme). \(existingMessage)."
        case let .testIdentifierInvalid(value):
            return
                "Invalid test identifiers \(value). The expected format is TestTarget[/TestClass[/TestMethod]]."
        case let .duplicatedTestTargets(targets):
            return
                "The target identifier cannot be specified both in --test-targets and --skip-test-targets (were specified: \(targets.map(\.description).joined(separator: ", ")))"
        case let .nothingToSkip(skippedTargets, includedTargets):
            return
                "Some of the targets specified in --skip-test-targets (\(skippedTargets.map(\.description).joined(separator: ", "))) will always be skipped as they are not included in the targets specified (\(includedTargets.map(\.description).joined(separator: ", ")))"
        case .actionInvalid:
            return "Cannot specify both --build-only and --without-building"
        case .testProductsNotFound:
            return "Could not find .xctestproducts bundle. Pass -derivedDataPath explicitly."
        case let .unspecifiedPlatform(target, platforms):
            return
                "Only single platform targets supported. The target \(target) specifies multiple supported platforms (\(platforms.joined(separator: ", ")))."
        case .shardPlanningRequiresBuildOnly:
            return
                "Shard planning flags (--shard-min/--shard-max/--shard-total) only apply when building tests for sharding. Pass --build-only to create a shard plan, or remove the shard flag(s) to run tests normally."
        case .shardIndexRequiresWithoutBuilding:
            return
                "--shard-index only applies when executing a previously built shard. Pass --without-building to run the shard, or remove --shard-index to run tests normally."
        case .shardingRequiresFullHandle:
            return
                "Test sharding requires a Tuist account. The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://tuist.dev/en/docs/guides/server/accounts-and-projects#projects"
        }
    }

    // Error type

    public var type: ErrorType {
        switch self {
        case .schemeNotFound, .schemeWithoutTestableTargets, .testPlanNotFound,
             .testIdentifierInvalid, .duplicatedTestTargets,
             .nothingToSkip, .actionInvalid, .testProductsNotFound, .unspecifiedPlatform,
             .shardPlanningRequiresBuildOnly, .shardIndexRequiresWithoutBuilding,
             .shardingRequiresFullHandle:
            return .abort
        }
    }
}

public struct TestService { // swiftlint:disable:this type_body_length
    private let generatorFactory: GeneratorFactorying
    private let cacheStorageFactory: CacheStorageFactorying
    private let xcodebuildController: XcodeBuildControlling
    private let buildGraphInspector: BuildGraphInspecting
    private let simulatorController: SimulatorControlling
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming
    private let xcResultService: XCResultServicing
    private let xcodeBuildAgumentParser: XcodeBuildArgumentParsing
    private let gitController: GitControlling
    private let rootDirectoryLocator: RootDirectoryLocating
    private let uploadResultBundleService: UploadResultBundleServicing
    private let derivedDataLocator: DerivedDataLocating
    private let createTestService: CreateTestServicing
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let ciController: CIControlling
    private let clock: Clock
    private let testQuarantineService: TestQuarantineServicing
    private let testCaseListService: TestCaseListServicing
    private let shardPlanService: ShardPlanServicing
    private let shardMatrixOutputService: ShardMatrixOutputServicing
    private let shardService: ShardServicing
    private let xcActivityLogController: XCActivityLogControlling
    private let uploadBuildRunService: UploadBuildRunServicing?

    public init(
        generatorFactory: GeneratorFactorying,
        cacheStorageFactory: CacheStorageFactorying
    ) {
        let manifestLoader = ManifestLoader.current
        let configLoader = ConfigLoader()
        self.init(
            generatorFactory: generatorFactory,
            cacheStorageFactory: cacheStorageFactory,
            configLoader: configLoader
        )
    }

    init(
        generatorFactory: GeneratorFactorying = GeneratorFactory(),
        cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory(),
        xcodebuildController: XcodeBuildControlling = XcodeBuildController(),
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        simulatorController: SimulatorControlling = SimulatorController(),
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider(),
        configLoader: ConfigLoading,
        fileSystem: FileSysteming = FileSystem(),
        xcResultService: XCResultServicing = XCResultService(),
        xcodeBuildArgumentParser: XcodeBuildArgumentParsing = XcodeBuildArgumentParser(),
        gitController: GitControlling = GitController(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        uploadResultBundleService: UploadResultBundleServicing = UploadResultBundleService(),
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
        createTestService: CreateTestServicing = CreateTestService(),
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        ciController: CIControlling = CIController(),
        clock: Clock = WallClock(),
        testQuarantineService: TestQuarantineServicing = TestQuarantineService(),
        testCaseListService: TestCaseListServicing = TestCaseListService(),
        shardPlanService: ShardPlanServicing = ShardPlanService(),
        shardMatrixOutputService: ShardMatrixOutputServicing = ShardMatrixOutputService(),
        shardService: ShardServicing = ShardService(),
        xcActivityLogController: XCActivityLogControlling = XCActivityLogController(),
        uploadBuildRunService: UploadBuildRunServicing? = UploadBuildRunService()
    ) {
        self.generatorFactory = generatorFactory
        self.cacheStorageFactory = cacheStorageFactory
        self.xcodebuildController = xcodebuildController
        self.buildGraphInspector = buildGraphInspector
        self.simulatorController = simulatorController
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.configLoader = configLoader
        self.fileSystem = fileSystem
        self.xcResultService = xcResultService
        xcodeBuildAgumentParser = xcodeBuildArgumentParser
        self.gitController = gitController
        self.rootDirectoryLocator = rootDirectoryLocator
        self.uploadResultBundleService = uploadResultBundleService
        self.derivedDataLocator = derivedDataLocator
        self.createTestService = createTestService
        self.machineEnvironment = machineEnvironment
        self.serverEnvironmentService = serverEnvironmentService
        self.ciController = ciController
        self.clock = clock
        self.testQuarantineService = testQuarantineService
        self.testCaseListService = testCaseListService
        self.shardPlanService = shardPlanService
        self.shardMatrixOutputService = shardMatrixOutputService
        self.shardService = shardService
        self.xcActivityLogController = xcActivityLogController
        self.uploadBuildRunService = uploadBuildRunService
    }

    public static func validateParameters(
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier]
    ) throws {
        let targetsIntersection = Set(testTargets)
            .intersection(skipTestTargets)
        if !targetsIntersection.isEmpty {
            throw TestServiceError.duplicatedTestTargets(targetsIntersection)
        }
    }

    // swiftlint:disable:next function_body_length
    public func run(
        runId: String,
        schemeName: String?,
        clean: Bool,
        noUpload: Bool,
        configuration: String?,
        path: AbsolutePath,
        deviceName: String?,
        platform: String?,
        osVersion: String?,
        action: XcodeBuildTestAction,
        rosetta: Bool,
        skipUITests: Bool,
        skipUnitTests: Bool,
        resultBundlePath: AbsolutePath?,
        derivedDataPath: String?,
        retryCount: Int,
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier],
        testPlanConfiguration: TestPlanConfiguration?,
        validateTestTargetsParameters: Bool = true,
        ignoreBinaryCache: Bool,
        ignoreSelectiveTesting: Bool,
        generateOnly: Bool,
        passthroughXcodeBuildArguments: [String],
        skipQuarantine: Bool = false,
        shardReference: String? = nil,
        shardGranularity: ShardGranularity = .module,
        shardMin: Int? = nil,
        shardMax: Int? = nil,
        shardTotal: Int? = nil,
        shardMaxDuration: Int? = nil,
        shardIndex: Int? = nil,
        shardSkipUpload: Bool = false,
        shardArchivePath: AbsolutePath? = nil,
        mode: TestProcessingMode? = nil
    ) async throws {
        if validateTestTargetsParameters {
            try Self.validateParameters(
                testTargets: testTargets,
                skipTestTargets: skipTestTargets
            )
        }

        let isSharding = shardMin != nil || shardMax != nil || shardTotal != nil
        if isSharding, action != .build {
            throw TestServiceError.shardPlanningRequiresBuildOnly
        }
        if shardIndex != nil, action != .testWithoutBuilding {
            throw TestServiceError.shardIndexRequiresWithoutBuilding
        }

        // Load config
        let config = try await configLoader.loadConfig(path: path)
            .assertingIsGeneratedProjectOrSwiftPackage(
                errorMessageOverride:
                "The 'tuist test' command is for generated projects or Swift packages. Please use 'tuist xcodebuild test' instead."
            )

        let mode = mode ?? TestProcessingMode.default(for: config.url)

        let (mutedQuarantinedTests, skippedQuarantinedTests) = try await fetchQuarantinedTests(
            skipQuarantine: skipQuarantine,
            config: config
        )
        let skipTestTargets = skipTestTargets + skippedQuarantinedTests

        if let shardIndex, action == .testWithoutBuilding {
            try await runShard(
                shardIndex: shardIndex,
                schemeName: schemeName,
                path: path,
                config: config,
                deviceName: deviceName,
                platform: platform,
                osVersion: osVersion,
                rosetta: rosetta,
                resultBundlePath: resultBundlePath,
                derivedDataPath: derivedDataPath,
                retryCount: retryCount,
                testTargets: testTargets,
                skipTestTargets: skipTestTargets,
                testPlanConfiguration: testPlanConfiguration,
                passthroughXcodeBuildArguments: passthroughXcodeBuildArguments,
                runId: runId,
                shardReference: shardReference,
                shardArchivePath: shardArchivePath,
                quarantinedTests: mutedQuarantinedTests,
                mode: mode
            )
            return
        }

        if action == .testWithoutBuilding,
           let testProductsPath = testProductsPathFromArguments(passthroughXcodeBuildArguments, relativeTo: path),
           try await fileSystem.exists(testProductsPath.appending(component: SelectiveTestingGraph.fileName))
        {
            try await runTestWithoutBuildingFromBundle(
                schemeName: schemeName,
                testProductsPath: testProductsPath,
                config: config,
                deviceName: deviceName,
                platform: platform,
                osVersion: osVersion,
                rosetta: rosetta,
                resultBundlePath: resultBundlePath,
                derivedDataPath: derivedDataPath,
                testTargets: testTargets,
                skipTestTargets: skipTestTargets,
                testPlanConfiguration: testPlanConfiguration,
                passthroughXcodeBuildArguments: passthroughXcodeBuildArguments,
                runId: runId,
                quarantinedTests: mutedQuarantinedTests,
                mode: mode
            )
            return
        }

        let cacheStorage = try await cacheStorageFactory.cacheStorage(config: config)

        let destination = try await destination(
            arguments: passthroughXcodeBuildArguments,
            deviceName: deviceName,
            osVersion: osVersion
        )

        let testGenerator = generatorFactory.testing(
            config: config,
            testPlan: testPlanConfiguration?.testPlan,
            includedTargets: Set(testTargets.map(\.target)),
            excludedTargets: Set(skipTestTargets.filter { $0.class == nil }.map(\.target)),
            skipUITests: skipUITests,
            skipUnitTests: skipUnitTests,
            configuration: configuration,
            ignoreBinaryCache: ignoreBinaryCache,
            ignoreSelectiveTesting: ignoreSelectiveTesting,
            cacheStorage: cacheStorage,
            destination: destination,
            schemeName: schemeName
        )

        Logger.current.notice("Generating project for testing", metadata: .section)
        let (_, graph, mapperEnvironment) = try await testGenerator.generateWithGraph(
            path: path,
            options: config.project.generatedProject?.generationOptions
        )

        if generateOnly {
            return
        }

        let graphTraverser = GraphTraverser(graph: graph)
        let version = osVersion?.version()
        let testableSchemes =
            buildGraphInspector.testableSchemes(graphTraverser: graphTraverser)
                + buildGraphInspector.workspaceSchemes(graphTraverser: graphTraverser)
        Logger.current.log(
            level: .debug,
            "Found the following testable schemes: \(Set(testableSchemes.map(\.name)).joined(separator: ", "))"
        )

        let currentPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        let derivedDataPath = try derivedDataPath.map {
            try AbsolutePath(
                validating: $0,
                relativeTo: currentPath
            )
        }

        let passedResultBundlePath = resultBundlePath

        let runResultBundlePath =
            try cacheDirectoriesProvider
                .cacheDirectory(for: .runs)
                .appending(components: runId, Constants.resultBundleName)

        let resultBundlePath = try await self.resultBundlePath(
            runResultBundlePath: runResultBundlePath,
            passedResultBundlePath: passedResultBundlePath,
            config: config
        )

        let schemes: [Scheme]
        let isolateHostlessUnitTests: Bool
        if let schemeName {
            guard let scheme = graphTraverser.schemes().first(where: { $0.name == schemeName })
            else {
                let schemes =
                    mapperEnvironment.initialGraph.map(GraphTraverser.init)?.schemes()
                        ?? graphTraverser.schemes()
                if let scheme = schemes.first(where: { $0.name == schemeName }) {
                    Logger.current.log(
                        level: .info,
                        "The scheme \(schemeName)'s test action has no tests to run, finishing early."
                    )
                    await updateTestServiceAnalytics(
                        mapperEnvironment: mapperEnvironment,
                        schemes: [scheme],
                        testPlanConfiguration: testPlanConfiguration,
                        action: action
                    )
                    try await outputEmptyShardMatrixIfNeeded(isSharding: isSharding, action: action)
                    return
                } else {
                    throw TestServiceError.schemeNotFound(
                        scheme: schemeName,
                        existing: Set(schemes.map(\.name)).map { $0 }
                    )
                }
            }

            await updateTestServiceAnalytics(
                mapperEnvironment: mapperEnvironment,
                schemes: [scheme],
                testPlanConfiguration: testPlanConfiguration,
                action: action
            )

            switch (
                testPlanConfiguration?.testPlan,
                scheme.testAction?.targets.isEmpty,
                scheme.testAction?.testPlans?.isEmpty
            ) {
            case (_, false, _), (_, _, false):
                break
            case (nil, true, _), (nil, nil, _):
                Logger.current.log(
                    level: .info,
                    "The scheme \(schemeName)'s test action has no tests to run, finishing early."
                )
                try await outputEmptyShardMatrixIfNeeded(isSharding: isSharding, action: action)
                return
            case (_?, _, true), (_?, _, nil):
                Logger.current.log(
                    level: .info,
                    "The scheme \(schemeName)'s test action has no test plans to run, finishing early."
                )
                try await outputEmptyShardMatrixIfNeeded(isSharding: isSharding, action: action)
                return
            default:
                break
            }

            schemes = [scheme]
            isolateHostlessUnitTests = false
        } else {
            let workspaceSchemes = buildGraphInspector.workspaceSchemes(graphTraverser: graphTraverser)
            let testableSchemes =
                buildGraphInspector.testableSchemes(graphTraverser: graphTraverser)
                    + workspaceSchemes
            (schemes, isolateHostlessUnitTests) = defaultSchemes(
                testableSchemes: testableSchemes,
                workspaceSchemes: workspaceSchemes,
                graphTraverser: graphTraverser,
                testPlanConfiguration: testPlanConfiguration,
                action: action
            )
            await updateTestServiceAnalytics(
                mapperEnvironment: mapperEnvironment,
                schemes: schemes,
                testPlanConfiguration: testPlanConfiguration,
                action: action
            )
        }

        if !shouldRunTest(
            for: schemes,
            testPlanConfiguration: testPlanConfiguration,
            mapperEnvironment: mapperEnvironment,
            graph: graph,
            action: action,
            requestedTestTargets: testTargets,
            passthroughXcodeBuildArguments: passthroughXcodeBuildArguments
        ) {
            if action == .build {
                try await outputEmptyShardMatrixIfNeeded(isSharding: isSharding, action: action)
            } else {
                let timer = clock.startTimer()
                try await uploadSkippedTestSummary(
                    schemeName: schemes.first?.name,
                    config: config,
                    timer: timer
                )
            }
            return
        }

        var passthroughXcodeBuildArguments = passthroughXcodeBuildArguments

        if isSharding, action == .build,
           !passthroughXcodeBuildArguments.contains("-testProductsPath")
        {
            let testProductsDir = try await fileSystem.makeTemporaryDirectory(prefix: "shard-test-products")
            let productsPath = testProductsDir.appending(component: "TestProducts.xctestproducts")
            passthroughXcodeBuildArguments += ["-testProductsPath", productsPath.pathString]
        }

        do {
            let didRunTests = try await testSchemes(
                schemes,
                graph: graph,
                mapperEnvironment: mapperEnvironment,
                cacheStorage: cacheStorage,
                clean: clean,
                noUpload: noUpload,
                configuration: configuration,
                version: version,
                deviceName: deviceName,
                platform: platform,
                action: action,
                rosetta: rosetta,
                resultBundlePath: resultBundlePath,
                derivedDataPath: derivedDataPath,
                retryCount: retryCount,
                testTargets: testTargets,
                skipTestTargets: skipTestTargets,
                testPlanConfiguration: testPlanConfiguration,
                passthroughXcodeBuildArguments: passthroughXcodeBuildArguments,
                config: config,
                quarantinedTests: mutedQuarantinedTests,
                isolateHostlessUnitTests: isolateHostlessUnitTests,
                mode: mode
            )
            if !didRunTests {
                if action == .build {
                    try await outputEmptyShardMatrixIfNeeded(isSharding: isSharding, action: action)
                } else {
                    let timer = clock.startTimer()
                    try await uploadSkippedTestSummary(
                        schemeName: schemes.first?.name,
                        config: config,
                        timer: timer
                    )
                }
                return
            }
        } catch {
            try await copyResultBundlePathIfNeeded(
                runResultBundlePath: runResultBundlePath,
                resultBundlePath: resultBundlePath
            )
            throw error
        }

        try await copyResultBundlePathIfNeeded(
            runResultBundlePath: runResultBundlePath,
            resultBundlePath: resultBundlePath
        )

        if action == .build {
            if let testProductsPath = try? await resolveTestProductsPath(
                passthroughXcodeBuildArguments: passthroughXcodeBuildArguments,
                derivedDataPath: derivedDataPath,
                relativeTo: path
            ) {
                let selectiveTestingGraph = computeSelectiveTestingGraph(
                    mapperEnvironment: mapperEnvironment,
                    schemes: schemes,
                    testPlanConfiguration: testPlanConfiguration
                )
                let selectiveTestingGraphPath = testProductsPath.appending(
                    component: SelectiveTestingGraph.fileName
                )
                try await fileSystem.writeAsJSON(selectiveTestingGraph, at: selectiveTestingGraphPath)

                await RunMetadataStorage.current.writeMetadata(to: testProductsPath)

                if isSharding,
                   let fullHandle = config.fullHandle
                {
                    let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
                    let buildRunId = await RunMetadataStorage.current.buildRunId
                    _ = try await shardPlanService.plan(
                        xctestproductsPath: testProductsPath,
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
        }
    }

    // MARK: - Quarantine

    private func fetchQuarantinedTests(
        skipQuarantine: Bool,
        config: Tuist
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
        let muted: [TestIdentifier]
        let skipped: [TestIdentifier]
        do {
            (muted, skipped) = try await (mutedTask, skippedTask)
        } catch {
            AlertController.current.warning(
                .alert("Failed to fetch quarantined tests: \(error.localizedDescription). Running all tests.")
            )
            return ([], [])
        }
        let total = muted.count + skipped.count
        if total > 0 {
            Logger.current.notice(
                "Found \(total) quarantined test(s): \(muted.count) muted, \(skipped.count) skipped",
                metadata: .subsection
            )
        }
        return (muted, skipped)
    }

    // MARK: - Shard Execute

    // swiftlint:disable:next function_body_length function_parameter_count
    private func runShard(
        shardIndex: Int,
        schemeName: String?,
        path: AbsolutePath,
        config: Tuist,
        deviceName: String?,
        platform: String?,
        osVersion: String?,
        rosetta: Bool,
        resultBundlePath: AbsolutePath?,
        derivedDataPath: String?,
        retryCount _: Int,
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier],
        testPlanConfiguration: TestPlanConfiguration?,
        passthroughXcodeBuildArguments: [String],
        runId: String,
        shardReference: String?,
        shardArchivePath: AbsolutePath?,
        quarantinedTests: [TestIdentifier],
        mode: TestProcessingMode
    ) async throws {
        guard let fullHandle = config.fullHandle else {
            throw TestServiceError.shardingRequiresFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        let localTestProductsPath = testProductsPathFromArguments(passthroughXcodeBuildArguments, relativeTo: path)
        let shard = try await shardService.shard(
            shardIndex: shardIndex,
            fullHandle: fullHandle,
            serverURL: serverURL,
            reference: shardReference,
            testProductsPath: localTestProductsPath,
            testProductsArchivePath: shardArchivePath
        )

        let cacheStorage = try await cacheStorageFactory.cacheStorage(config: config)

        let runResultBundlePath =
            try cacheDirectoriesProvider
                .cacheDirectory(for: .runs)
                .appending(components: runId, Constants.resultBundleName)

        let resultBundlePath = try await self.resultBundlePath(
            runResultBundlePath: runResultBundlePath,
            passedResultBundlePath: resultBundlePath,
            config: config
        )

        let shardCurrentPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        let derivedDataPath = try derivedDataPath.map {
            try AbsolutePath(
                validating: $0,
                relativeTo: shardCurrentPath
            )
        }

        await RunMetadataStorage.current.restoreMetadata(from: shard.testProductsPath)

        let xcodebuildArguments = try await buildTestWithoutBuildingArguments(
            testProductsPath: shard.testProductsPath,
            testTargets: testTargets,
            skipTestTargets: skipTestTargets,
            shardTestIdentifiers: shard.testIdentifiers,
            shardSkipTestIdentifiers: shard.skipTestIdentifiers,
            testPlanConfiguration: testPlanConfiguration,
            deviceName: deviceName,
            platform: platform,
            osVersion: osVersion,
            rosetta: rosetta,
            resultBundlePath: resultBundlePath,
            derivedDataPath: derivedDataPath,
            passthroughXcodeBuildArguments: passthroughXcodeBuildArguments
        )

        var testError: Error?

        do {
            try await xcodebuildController.run(arguments: xcodebuildArguments)
        } catch {
            testError = error
        }

        let summary = mode == .local
            ? await testSummary(resultBundlePath: resultBundlePath, quarantinedTests: quarantinedTests)
            : nil
        await uploadResultBundleIfNeeded(
            testSummary: summary,
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: derivedDataPath,
            config: config,
            action: .testWithoutBuilding,
            scheme: schemeName,
            shardPlanId: shard.shardPlanId,
            shardIndex: shardIndex,
            mode: mode
        )

        if let selectiveTestingGraph = shard.selectiveTestingGraph {
            try await storeSuccessfulTestHashesFromGraph(
                selectiveTestingGraph: selectiveTestingGraph,
                passingTargetNames: await passingTargetNames(resultBundlePath: resultBundlePath),
                cacheStorage: cacheStorage
            )
        }

        try await copyResultBundlePathIfNeeded(
            runResultBundlePath: runResultBundlePath,
            resultBundlePath: resultBundlePath
        )
        // Only Tuist-owned products (downloaded or extracted) are cleaned up; user-provided local
        // products (passed via -testProductsPath) are left in place.
        if localTestProductsPath == nil {
            try? await fileSystem.remove(shard.testProductsPath)
        }

        if let testError {
            throw testError
        }

        AlertController.current.success(.alert("The project tests ran successfully"))
    }

    // MARK: - Test Without Building (from bundle)

    // swiftlint:disable:next function_body_length function_parameter_count
    private func runTestWithoutBuildingFromBundle(
        schemeName: String?,
        testProductsPath: AbsolutePath,
        config: Tuist,
        deviceName: String?,
        platform: String?,
        osVersion: String?,
        rosetta: Bool,
        resultBundlePath: AbsolutePath?,
        derivedDataPath: String?,
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier],
        testPlanConfiguration: TestPlanConfiguration?,
        passthroughXcodeBuildArguments: [String],
        runId: String,
        quarantinedTests: [TestIdentifier],
        mode: TestProcessingMode
    ) async throws {
        Logger.current.notice(
            "Skipping project generation, using selective testing graph from .xctestproducts bundle...",
            metadata: .section
        )

        let selectiveTestingGraphPath = testProductsPath.appending(component: SelectiveTestingGraph.fileName)
        let selectiveTestingGraph: SelectiveTestingGraph = try await fileSystem.readJSONFile(
            at: selectiveTestingGraphPath
        )

        await RunMetadataStorage.current.restoreMetadata(from: testProductsPath)

        let cacheStorage = try await cacheStorageFactory.cacheStorage(config: config)

        let runResultBundlePath =
            try cacheDirectoriesProvider
                .cacheDirectory(for: .runs)
                .appending(components: runId, Constants.resultBundleName)

        let resultBundlePath = try await self.resultBundlePath(
            runResultBundlePath: runResultBundlePath,
            passedResultBundlePath: resultBundlePath,
            config: config
        )

        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let derivedDataPath = try derivedDataPath.map {
            try AbsolutePath(
                validating: $0,
                relativeTo: currentWorkingDirectory
            )
        }

        let xcodebuildArguments = try await buildTestWithoutBuildingArguments(
            testProductsPath: testProductsPath,
            testTargets: testTargets,
            skipTestTargets: skipTestTargets,
            testPlanConfiguration: testPlanConfiguration,
            deviceName: deviceName,
            platform: platform,
            osVersion: osVersion,
            rosetta: rosetta,
            resultBundlePath: resultBundlePath,
            derivedDataPath: derivedDataPath,
            passthroughXcodeBuildArguments: passthroughXcodeBuildArguments
        )

        let requestedTestPlan = testPlanConfiguration?.testPlan
        let requestedTestPlanOrScheme = requestedTestPlan ?? schemeName
        if let requestedTestPlanOrScheme,
           selectiveTestingGraph.attemptedTestPlans.contains(requestedTestPlanOrScheme),
           try await !bundleHasXCTestRun(
               for: requestedTestPlanOrScheme,
               isTestPlan: requestedTestPlan != nil,
               in: testProductsPath
           )
        {
            let timer = clock.startTimer()
            try await uploadSkippedTestSummary(
                schemeName: requestedTestPlanOrScheme,
                config: config,
                timer: timer
            )
            AlertController.current.success(
                .alert("All selected tests matched previously successful hashes, skipping execution")
            )
            return
        }

        var testError: Error?

        do {
            try await xcodebuildController.run(arguments: xcodebuildArguments)
        } catch {
            testError = error
        }

        let summary = mode == .local
            ? await testSummary(resultBundlePath: resultBundlePath, quarantinedTests: quarantinedTests)
            : nil
        await uploadResultBundleIfNeeded(
            testSummary: summary,
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: derivedDataPath,
            config: config,
            action: .testWithoutBuilding,
            scheme: schemeName,
            mode: mode
        )

        try await storeSuccessfulTestHashesFromGraph(
            selectiveTestingGraph: selectiveTestingGraph,
            passingTargetNames: await passingTargetNames(resultBundlePath: resultBundlePath),
            cacheStorage: cacheStorage
        )

        try await copyResultBundlePathIfNeeded(
            runResultBundlePath: runResultBundlePath,
            resultBundlePath: resultBundlePath
        )

        if let testError {
            throw testError
        }

        AlertController.current.success(.alert("The project tests ran successfully"))
    }

    private func testProductsPathFromArguments(_ arguments: [String], relativeTo path: AbsolutePath) -> AbsolutePath? {
        guard let index = arguments.firstIndex(of: "-testProductsPath"),
              arguments.indices.contains(index + 1)
        else { return nil }
        let value = arguments[index + 1]
        if let absolute = try? AbsolutePath(validating: value) {
            return absolute
        }
        return try? AbsolutePath(validating: value, relativeTo: path)
    }

    private func buildTestWithoutBuildingArguments(
        testProductsPath: AbsolutePath,
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier],
        shardTestIdentifiers: [String] = [],
        shardSkipTestIdentifiers: [String] = [],
        testPlanConfiguration: TestPlanConfiguration?,
        deviceName: String?,
        platform: String?,
        osVersion: String?,
        rosetta: Bool,
        resultBundlePath: AbsolutePath?,
        derivedDataPath: AbsolutePath?,
        passthroughXcodeBuildArguments: [String]
    ) async throws -> [String] {
        var arguments = ["test-without-building"]
        if !passthroughXcodeBuildArguments.contains("-testProductsPath"),
           !passthroughXcodeBuildArguments.contains("-xctestrun")
        {
            arguments += ["-testProductsPath", testProductsPath.pathString]
        }

        for testTarget in testTargets {
            arguments += ["-only-testing", testTarget.description]
        }
        for shardTestIdentifier in shardTestIdentifiers {
            arguments += ["-only-testing", shardTestIdentifier]
        }
        // The catch-all shard carries no `-only-testing` and instead skips every suite assigned to
        // other shards, so it runs everything not explicitly assigned (newly added or un-enumerated
        // suites included). Without applying these, `tuist test` sharding runs the wrong set.
        for shardSkipTestIdentifier in shardSkipTestIdentifiers {
            arguments += ["-skip-testing", shardSkipTestIdentifier]
        }
        for skipTarget in skipTestTargets {
            arguments += ["-skip-testing", skipTarget.description]
        }
        if let testPlanConfiguration {
            arguments += ["-testPlan", testPlanConfiguration.testPlan]
        }

        if !passthroughXcodeBuildArguments.contains("-destination") {
            let destination = try await destination(
                arguments: passthroughXcodeBuildArguments,
                deviceName: deviceName,
                osVersion: osVersion
            )
            if let destination {
                arguments += [
                    "-destination",
                    "platform=iOS Simulator,id=\(destination.device.udid)",
                ]
            } else if let platform {
                let buildPlatform = try XcodeGraph.Platform.from(commandLineValue: platform)
                arguments += ["-destination", buildPlatform.xcodebuildPlatformDestination]
            }
        }

        if rosetta {
            arguments += ["-arch", "x86_64"]
        }

        if let resultBundlePath {
            arguments += ["-resultBundlePath", resultBundlePath.pathString]
        }

        if let derivedDataPath {
            arguments += ["-derivedDataPath", derivedDataPath.pathString]
        }

        arguments += passthroughXcodeBuildArguments
        return arguments
    }

    private func resolveTestProductsPath(
        passthroughXcodeBuildArguments: [String],
        derivedDataPath: AbsolutePath?,
        relativeTo path: AbsolutePath
    ) async throws -> AbsolutePath {
        if let testProductsPath = testProductsPathFromArguments(
            passthroughXcodeBuildArguments,
            relativeTo: path
        ) {
            return testProductsPath
        }

        guard let derivedDataPath else {
            throw TestServiceError.testProductsNotFound
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
            throw TestServiceError.testProductsNotFound
        }
        return match
    }

    private func computeSelectiveTestingGraph(
        mapperEnvironment: MapperEnvironment,
        schemes: [Scheme],
        testPlanConfiguration: TestPlanConfiguration?
    ) -> SelectiveTestingGraph {
        guard let initialGraph = mapperEnvironment.initialGraph else {
            let attemptedTestPlans = attemptedTestPlans(
                schemes: schemes,
                testPlanConfiguration: testPlanConfiguration
            )
            return SelectiveTestingGraph(
                testTargetHashes: [:],
                attemptedTestPlans: attemptedTestPlans
            )
        }

        let graphTraverser = GraphTraverser(graph: initialGraph)
        let initialSchemes = graphTraverser.schemes()
        let matchingSchemes = initialSchemes.filter { initialScheme in
            schemes.contains(where: { $0.name == initialScheme.name })
        }
        let attemptedTestPlans = attemptedTestPlans(
            schemes: matchingSchemes,
            testPlanConfiguration: testPlanConfiguration
        )
        let allTestTargets = matchingSchemes.flatMap {
            testActionTargetReferences(scheme: $0, testPlanConfiguration: testPlanConfiguration, action: .build)
        }
        .compactMap { ref -> GraphTarget? in
            guard let project = initialGraph.projects[ref.projectPath],
                  let target = project.targets[ref.name]
            else { return nil }
            return GraphTarget(path: ref.projectPath, target: target, project: project)
        }

        let testTargetHashes: [String: String] = allTestTargets.reduce(into: [:]) { result, testTarget in
            if let hash = mapperEnvironment.targetTestHashes[testTarget.path]?[testTarget.target.name] {
                result[testTarget.target.name] = hash
            }
        }

        return SelectiveTestingGraph(
            testTargetHashes: testTargetHashes,
            attemptedTestPlans: attemptedTestPlans
        )
    }

    private func attemptedTestPlans(
        schemes: [Scheme],
        testPlanConfiguration: TestPlanConfiguration?
    ) -> [String] {
        if let testPlan = testPlanConfiguration?.testPlan {
            return [testPlan]
        }
        var names: [String] = []
        var seen: Set<String> = []
        for scheme in schemes {
            let plans = scheme.testAction?.testPlans ?? []
            if plans.isEmpty {
                if seen.insert(scheme.name).inserted {
                    names.append(scheme.name)
                }
            } else {
                for plan in plans where seen.insert(plan.name).inserted {
                    names.append(plan.name)
                }
            }
        }
        return names
    }

    private func bundleHasXCTestRun(
        for planOrSchemeName: String,
        isTestPlan: Bool,
        in testProductsPath: AbsolutePath
    ) async throws -> Bool {
        let xctestrunPaths = try await fileSystem
            .glob(directory: testProductsPath, include: ["**/*.xctestrun"])
            .collect()
        return xctestrunPaths.contains { path in
            let basename = path.basenameWithoutExt
            if isTestPlan {
                // With test plans Xcode emits `<plan>.xctestrun`.
                return basename == planOrSchemeName
            }
            // Without plans Xcode emits `<scheme>_<destination>.xctestrun`.
            return basename == planOrSchemeName || basename.hasPrefix("\(planOrSchemeName)_")
        }
    }

    private func storeSuccessfulTestHashesFromGraph(
        selectiveTestingGraph: SelectiveTestingGraph,
        passingTargetNames: Set<String>,
        cacheStorage: CacheStoring
    ) async throws {
        let cacheableItems: [CacheStorableItem: [AbsolutePath]] = passingTargetNames
            .compactMap { name -> (CacheStorableItem, [AbsolutePath])? in
                guard let hash = selectiveTestingGraph.testTargetHashes[name] else { return nil }
                return (CacheStorableItem(name: name, hash: hash), [])
            }
            .reduce(into: [:]) { $0[$1.0] = $1.1 }

        guard !cacheableItems.isEmpty else { return }
        try await cacheStorage.store(cacheableItems, cacheCategory: .selectiveTests)
    }

    private func passingTargetNames(resultBundlePath: AbsolutePath?) async -> Set<String> {
        guard let resultBundlePath else { return [] }
        let rootDirectory = try? await rootDirectory()
        guard let rootDirectory,
              let testSummary = try? await xcResultService.parse(path: resultBundlePath, rootDirectory: rootDirectory)
        else { return [] }

        let testCasesByModule = Dictionary(grouping: testSummary.testCases) { $0.module }
        return Set(
            testCasesByModule.compactMap { module, testCases -> String? in
                guard let module else { return nil }
                return testCases.allSatisfy { $0.status != .failed } ? module : nil
            }
        )
    }

    // MARK: - Helpers

    private func testSchemes(
        _ schemes: [Scheme],
        graph: Graph,
        mapperEnvironment: MapperEnvironment,
        cacheStorage: CacheStoring,
        clean: Bool,
        noUpload: Bool,
        configuration: String?,
        version: Version?,
        deviceName: String?,
        platform: String?,
        action: XcodeBuildTestAction,
        rosetta: Bool,
        resultBundlePath: AbsolutePath?,
        derivedDataPath: AbsolutePath?,
        retryCount: Int,
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier],
        testPlanConfiguration: TestPlanConfiguration?,
        passthroughXcodeBuildArguments: [String],
        config: Tuist,
        quarantinedTests: [TestIdentifier],
        isolateHostlessUnitTests: Bool = false,
        mode: TestProcessingMode = .local
    ) async throws -> Bool {
        let graphTraverser = GraphTraverser(graph: graph)

        guard !schemes.isEmpty else {
            return false
        }

        let uploadCacheStorage: CacheStoring
        if noUpload {
            uploadCacheStorage = try await cacheStorageFactory.cacheLocalStorage()
        } else {
            uploadCacheStorage = cacheStorage
        }

        do {
            let passthroughDerivedDataPath = try? await xcodeBuildAgumentParser
                .parse(passthroughXcodeBuildArguments)
                .derivedDataPath
            let hostlessDerivedDataBasePath = derivedDataPath ?? passthroughDerivedDataPath
            var didRunTests = false
            for testScheme in schemes {
                let testSchemeTargetNames = Set(
                    testActionTargetReferences(
                        scheme: testScheme,
                        testPlanConfiguration: testPlanConfiguration,
                        action: action
                    )
                    .map(\.name)
                )
                if testSchemeTargetNames.isEmpty {
                    continue
                }

                let testSchemeTestTargets = testTargets.filter {
                    testSchemeTargetNames.contains($0.target)
                }

                if !testTargets.isEmpty, testSchemeTestTargets.isEmpty {
                    continue
                }

                didRunTests = true

                // A host-less unit-test bundle crashes during xctest bootstrap when its build-products
                // directory also contains the app's frameworks (e.g. swift-sharing). When such a scheme is
                // split out of a mixed workspace scheme, run it against its own derived data so its products
                // directory stays clean. An explicit derived data path is honored by nesting under it.
                let schemeDerivedDataPath: AbsolutePath?
                if isolateHostlessUnitTests, isHostlessUnitTestScheme(
                    scheme: testScheme,
                    graphTraverser: graphTraverser,
                    testPlanConfiguration: testPlanConfiguration,
                    action: action
                ) {
                    if let hostlessDerivedDataBasePath {
                        schemeDerivedDataPath = hostlessDerivedDataBasePath
                            .appending(components: "HostlessTests", testScheme.name)
                    } else {
                        schemeDerivedDataPath = try await fileSystem
                            .makeTemporaryDirectory(prefix: "hostless-tests")
                    }
                } else {
                    schemeDerivedDataPath = derivedDataPath
                }

                try await self.testScheme(
                    scheme: testScheme,
                    graphTraverser: graphTraverser,
                    clean: clean,
                    configuration: configuration,
                    version: version,
                    deviceName: deviceName,
                    platform: platform,
                    action: action,
                    rosetta: rosetta,
                    resultBundlePath: resultBundlePath,
                    derivedDataPath: schemeDerivedDataPath,
                    retryCount: retryCount,
                    testTargets: testSchemeTestTargets,
                    skipTestTargets: skipTestTargets,
                    testPlanConfiguration: testPlanConfiguration,
                    passthroughXcodeBuildArguments: passthroughXcodeBuildArguments,
                    config: config,
                    quarantinedTests: quarantinedTests,
                    mode: mode
                )
            }
            guard didRunTests else {
                return false
            }
        } catch {
            guard action != .build, let resultBundlePath else { throw error }

            guard try await fileSystem.exists(resultBundlePath) else { throw error }

            let testStatuses = try await xcResultService.parseTestStatuses(path: resultBundlePath)
            guard !testStatuses.testCases.isEmpty else { throw error }

            let testTargets = testActionTargets(
                for: schemes, testPlanConfiguration: testPlanConfiguration, graph: graph, action: action
            )

            let passingTestTargets = testTargets.filter {
                testStatuses.passingModuleNames().contains($0.target.name)
            }

            try await storeSuccessfulTestHashes(
                for: passingTestTargets,
                graph: graph,
                mapperEnvironment: mapperEnvironment,
                cacheStorage: uploadCacheStorage
            )

            if testQuarantineService.onlyQuarantinedTestsFailed(testStatuses: testStatuses, quarantinedTests: quarantinedTests) {
                return true
            }

            throw error
        }

        if action != .build {
            try await storeSuccessfulTestHashes(
                for: testActionTargets(
                    for: schemes, testPlanConfiguration: testPlanConfiguration, graph: graph, action: action
                ),
                graph: graph,
                mapperEnvironment: mapperEnvironment,
                cacheStorage: uploadCacheStorage
            )
        }

        let verb =
            switch action {
            case .test, .testWithoutBuilding:
                "ran"
            case .build:
                "built"
            }

        if !quarantinedTests.isEmpty {
            AlertController.current.success(
                .alert("The project tests \(verb) successfully (including \(quarantinedTests.count) quarantined test(s))")
            )
        } else {
            AlertController.current.success(.alert("The project tests \(verb) successfully"))
        }

        return true
    }

    private func updateTestServiceAnalytics(
        mapperEnvironment: MapperEnvironment,
        schemes: [Scheme],
        testPlanConfiguration: TestPlanConfiguration?,
        action: XcodeBuildTestAction
    ) async {
        let initialTestTargets = initialTestTargets(
            mapperEnvironment: mapperEnvironment,
            schemes: schemes,
            testPlanConfiguration: testPlanConfiguration,
            action: action
        )

        await RunMetadataStorage.current.update(
            selectiveTestingCacheItems: initialTestTargets.reduce(into: [:]) { result, element in
                guard let hash = mapperEnvironment.targetTestHashes[element.path]?[
                    element.target.name
                ]
                else { return }
                let cacheItem =
                    mapperEnvironment.targetTestCacheItems[element.path]?[element.target.name]
                        ?? CacheItem(
                            name: element.target.name,
                            hash: hash,
                            source: .miss,
                            cacheCategory: .selectiveTests
                        )
                result[element.path, default: [:]][element.target.name] = cacheItem
            }
        )
    }

    private func copyResultBundlePathIfNeeded(
        runResultBundlePath: AbsolutePath?,
        resultBundlePath: AbsolutePath?
    ) async throws {
        if let runResultBundlePath, let resultBundlePath, runResultBundlePath != resultBundlePath {
            guard try await fileSystem.exists(resultBundlePath) else { return }
            if try await !fileSystem.exists(resultBundlePath.parentDirectory) {
                try await fileSystem.makeDirectory(at: resultBundlePath.parentDirectory)
            }
            try await fileSystem.copy(
                try await fileSystem.resolveSymbolicLink(resultBundlePath),
                to: runResultBundlePath.parentDirectory.appending(
                    components: "\(Constants.resultBundleName).xcresult"
                )
            )
        }
    }

    private func outputEmptyShardMatrixIfNeeded(isSharding: Bool, action: XcodeBuildTestAction) async throws {
        if isSharding, action == .build {
            try await shardMatrixOutputService.output(
                Components.Schemas.ShardPlan(
                    id: "",
                    reference: "",
                    shard_count: 0,
                    shards: [],
                    upload_url: ""
                )
            )
        }
    }

    private func defaultSchemes(
        testableSchemes: [Scheme],
        workspaceSchemes: [Scheme],
        graphTraverser: GraphTraversing,
        testPlanConfiguration: TestPlanConfiguration?,
        action: XcodeBuildTestAction
    ) -> (schemes: [Scheme], isolatedHostlessUnitTests: Bool) {
        guard action != .build,
              containsMixedHostedAndHostlessUnitTests(
                  schemes: workspaceSchemes,
                  graphTraverser: graphTraverser,
                  testPlanConfiguration: testPlanConfiguration,
                  action: action
              )
        else {
            return (workspaceSchemes, false)
        }

        let workspaceSchemeNames = Set(workspaceSchemes.map(\.name))
        let workspaceTestTargets = Set(
            workspaceSchemes.flatMap {
                testActionTargetReferences(
                    scheme: $0,
                    testPlanConfiguration: testPlanConfiguration,
                    action: action
                )
            }
        )
        let projectSchemes = testableSchemes.filter {
            guard !workspaceSchemeNames.contains($0.name) else {
                return false
            }

            let schemeTestTargets = Set(
                testActionTargetReferences(
                    scheme: $0,
                    testPlanConfiguration: testPlanConfiguration,
                    action: action
                )
            )
            return !schemeTestTargets.isDisjoint(with: workspaceTestTargets)
        }
        guard !projectSchemes.isEmpty else {
            return (workspaceSchemes, false)
        }

        Logger.current.debug(
            "Workspace schemes include hosted tests and host-less unit tests; running generated project schemes separately."
        )
        return (projectSchemes, action == .test)
    }

    /// A scheme is host-less when at least one of its test targets is a `.unitTests` bundle that has
    /// dependencies but no host application. Such a bundle crashes during xctest bootstrap when it runs
    /// against a build-products directory that also contains the app's frameworks (see swift-sharing),
    /// so it must be isolated into its own derived data when split out of the workspace scheme.
    private func isHostlessUnitTestScheme(
        scheme: Scheme,
        graphTraverser: GraphTraversing,
        testPlanConfiguration: TestPlanConfiguration?,
        action: XcodeBuildTestAction
    ) -> Bool {
        testActionTargetReferences(
            scheme: scheme,
            testPlanConfiguration: testPlanConfiguration,
            action: action
        ).contains { targetReference in
            guard let graphTarget = graphTraverser.target(
                path: targetReference.projectPath,
                name: targetReference.name
            ), graphTarget.target.product == .unitTests else {
                return false
            }

            let dependencies = graphTraverser
                .directTargetDependencies(path: graphTarget.path, name: graphTarget.target.name)
            return !dependencies.isEmpty && !dependencies.contains(where: { $0.target.product.canHostTests() })
        }
    }

    private func containsMixedHostedAndHostlessUnitTests(
        schemes: [Scheme],
        graphTraverser: GraphTraversing,
        testPlanConfiguration: TestPlanConfiguration?,
        action: XcodeBuildTestAction
    ) -> Bool {
        schemes.contains { scheme in
            let testTargets = testActionTargetReferences(
                scheme: scheme,
                testPlanConfiguration: testPlanConfiguration,
                action: action
            )

            var hasHostedTests = false
            var hasHostlessUnitTests = false

            for targetReference in testTargets {
                guard let graphTarget = graphTraverser.target(
                    path: targetReference.projectPath,
                    name: targetReference.name
                ) else {
                    continue
                }

                let dependencies = graphTraverser
                    .directTargetDependencies(path: graphTarget.path, name: graphTarget.target.name)

                if dependencies.contains(where: { $0.target.product.canHostTests() }) {
                    hasHostedTests = true
                } else if graphTarget.target.product == .unitTests, !dependencies.isEmpty {
                    hasHostlessUnitTests = true
                }

                if hasHostedTests, hasHostlessUnitTests {
                    return true
                }
            }

            return false
        }
    }

    private func shouldRunTest(
        for schemes: [Scheme],
        testPlanConfiguration: TestPlanConfiguration?,
        mapperEnvironment: MapperEnvironment,
        graph: Graph,
        action: XcodeBuildTestAction,
        requestedTestTargets: [TestIdentifier] = [],
        passthroughXcodeBuildArguments: [String] = []
    ) -> Bool {
        let testActionTargets = testActionTargets(
            for: schemes,
            testPlanConfiguration: testPlanConfiguration,
            graph: graph,
            action: action
        )
        .map(\.target)

        if schemes.isEmpty {
            Logger.current.log(level: .info, "There are no tests to run, finishing early")
            return false
        }

        let requestedTargetNames = Set(requestedTestTargets.map(\.target))
        let skippedBySelectiveTesting = initialTestTargets(
            mapperEnvironment: mapperEnvironment,
            schemes: schemes,
            testPlanConfiguration: testPlanConfiguration,
            action: action
        )
        .filter { target in
            !testActionTargets.contains(where: {
                $0.bundleId == target.target.bundleId
            })
        }
        .filter { target in
            requestedTargetNames.isEmpty || requestedTargetNames.contains(target.target.name)
        }

        if !skippedBySelectiveTesting.isEmpty {
            Logger.current
                .notice(
                    "The following targets have not changed since the last successful run and will be skipped: \(skippedBySelectiveTesting.map(\.target.name).sorted().joined(separator: ", "))"
                )
        }

        let passthroughSkippedTargetNames = passthroughSkippedTestTargetNames(passthroughXcodeBuildArguments)
        let targetsAfterPassthroughSkip = testActionTargets
            .filter { !passthroughSkippedTargetNames.contains($0.name) }

        if targetsAfterPassthroughSkip.isEmpty, !testActionTargets.isEmpty {
            Logger.current
                .notice(
                    "All test targets selected by selective testing are excluded by -skip-testing in the xcodebuild passthrough arguments, finishing early"
                )
            return false
        }

        let testedTargetNames = targetsAfterPassthroughSkip.map(\.name).sorted()
        if !testedTargetNames.isEmpty {
            Logger.current
                .notice(
                    "Testing the following targets: \(testedTargetNames.joined(separator: ", "))"
                )
        }

        return true
    }

    private func passthroughSkippedTestTargetNames(_ arguments: [String]) -> Set<String> {
        passthroughSkipTestingValues(arguments)
            .compactMap { try? TestIdentifier(string: $0) }
            // Only whole-target skips (no `/Class` or `/Class/Method`) remove a target entirely.
            .filter { $0.class == nil && $0.method == nil }
            .reduce(into: Set<String>()) { $0.insert($1.target) }
    }

    private func passthroughSkipTestingValues(_ arguments: [String]) -> [String] {
        var values: [String] = []
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == "-skip-testing", let value = iterator.next() {
                values.append(value)
            } else if argument.hasPrefix("-skip-testing:") {
                values.append(String(argument.dropFirst("-skip-testing:".count)))
            }
        }
        return values
    }

    private func initialTestTargets(
        mapperEnvironment: MapperEnvironment,
        schemes: [Scheme],
        testPlanConfiguration: TestPlanConfiguration?,
        action: XcodeBuildTestAction
    ) -> [GraphTarget] {
        guard let initialGraph = mapperEnvironment.initialGraph else { return [] }
        let initialSchemes = GraphTraverser(graph: initialGraph).schemes()
        return testActionTargets(
            for:
            initialSchemes
                .filter { initialScheme in
                    schemes.contains(where: { $0.name == initialScheme.name })
                },
            testPlanConfiguration: testPlanConfiguration,
            graph: initialGraph,
            action: action
        )
    }

    private func testActionTargets(
        for schemes: [Scheme],
        testPlanConfiguration: TestPlanConfiguration?,
        graph: Graph,
        action: XcodeBuildTestAction
    ) -> [GraphTarget] {
        return
            schemes
                .flatMap {
                    testActionTargetReferences(scheme: $0, testPlanConfiguration: testPlanConfiguration, action: action)
                }
                .compactMap {
                    guard let project = graph.projects[$0.projectPath],
                          let target = project.targets[$0.name]
                    else {
                        return nil
                    }
                    return GraphTarget(path: project.path, target: target, project: project)
                }
    }

    private func testActionTargetReferences(
        scheme: Scheme,
        testPlanConfiguration: TestPlanConfiguration?,
        action: XcodeBuildTestAction
    ) -> [TargetReference] {
        return if let testPlanConfiguration {
            scheme.testAction?.testPlans?
                .first(
                    where: { $0.name == testPlanConfiguration.testPlan }
                )?.testTargets.map(\.target) ?? []
        } else if action == .build, let testPlans = scheme.testAction?.testPlans {
            // If we are building a scheme that has testplans but none specified then we should return all test targets
            testPlans.flatMap(\.testTargets).map(\.target)
        } else if let defaultTestPlan = scheme.testAction?.testPlans?.first(where: {
            $0.isDefault
        }) {
            defaultTestPlan.testTargets.map(\.target)
        } else if let testActionTargets = scheme.testAction?.targets.map(\.target),
                  !testActionTargets.isEmpty
        {
            testActionTargets
        } else {
            [TargetReference]()
        }
    }

    private func storeSuccessfulTestHashes(
        for targets: [GraphTarget],
        graph _: Graph,
        mapperEnvironment: MapperEnvironment,
        cacheStorage: CacheStoring
    ) async throws {
        guard let initialGraph = mapperEnvironment.initialGraph else { return }

        let testedGraphTargets: [GraphTarget] = targets.compactMap {
            guard let project = initialGraph.projects[$0.path],
                  let target = project.targets[$0.target.name]
            else { return nil }
            return GraphTarget(path: $0.path, target: target, project: project)
        }
        try await fileSystem.runInTemporaryDirectory(prefix: "test") { _ in
            let hashes =
                testedGraphTargets
                    .filter {
                        return mapperEnvironment.targetTestCacheItems[$0.path]?[$0.target.name] == nil
                    }
                    .compactMap { graphTarget -> (target: Target, hash: String)? in
                        guard let hash = mapperEnvironment.targetTestHashes[graphTarget.path]?[
                            graphTarget.target.name
                        ]
                        else { return nil }
                        return (target: graphTarget.target, hash: hash)
                    }

            let cacheableItems: [CacheStorableItem: [AbsolutePath]] =
                hashes
                    .reduce(into: [:]) { acc, element in
                        acc[CacheStorableItem(name: element.target.name, hash: element.hash)] = [
                            AbsolutePath
                        ]()
                    }

            try await cacheStorage.store(cacheableItems, cacheCategory: .selectiveTests)
        }
    }

    /// - Returns: Result bundle path to use. Either passed by the user or a path in the Tuist cache
    private func resultBundlePath(
        runResultBundlePath: AbsolutePath,
        passedResultBundlePath: AbsolutePath?,
        config: Tuist
    ) async throws -> AbsolutePath? {
        if config.fullHandle == nil {
            return passedResultBundlePath
        } else {
            return passedResultBundlePath ?? runResultBundlePath
        }
    }

    // swiftlint:disable:next function_body_length
    private func testScheme(
        scheme: Scheme,
        graphTraverser: GraphTraversing,
        clean: Bool,
        configuration: String?,
        version: Version?,
        deviceName: String?,
        platform: String?,
        action: XcodeBuildTestAction,
        rosetta: Bool,
        resultBundlePath: AbsolutePath?,
        derivedDataPath: AbsolutePath?,
        retryCount: Int,
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier],
        testPlanConfiguration: TestPlanConfiguration?,
        passthroughXcodeBuildArguments: [String],
        config: Tuist,
        quarantinedTests: [TestIdentifier],
        mode: TestProcessingMode = .local
    ) async throws {
        Logger.current.log(
            level: .notice, "\(action.description) scheme \(scheme.name)", metadata: .section
        )
        if let testPlan = testPlanConfiguration?.testPlan,
           let testPlans = scheme.testAction?.testPlans,
           !testPlans.contains(where: { $0.name == testPlan })
        {
            throw TestServiceError.testPlanNotFound(
                scheme: scheme.name,
                testPlan: testPlan,
                existing: testPlans.map(\.name)
            )
        }
        guard let buildableTarget = buildGraphInspector.testableTarget(
            scheme: scheme,
            testPlan: testPlanConfiguration?.testPlan,
            testTargets: testTargets,
            skipTestTargets: skipTestTargets,
            graphTraverser: graphTraverser,
            action: action
        )
        else {
            if action == .build {
                Logger.current.notice(
                    "The scheme \(scheme.name) has no testable targets to build, skipping."
                )
                return
            }
            throw TestServiceError.schemeWithoutTestableTargets(
                scheme: scheme.name, testPlan: testPlanConfiguration?.testPlan
            )
        }

        let buildPlatform: XcodeGraph.Platform

        if let platform {
            buildPlatform = try XcodeGraph.Platform.from(commandLineValue: platform)
        } else if let resolvedPlatform = buildableTarget.target.destinations.first?.platform,
                  buildableTarget.target.destinations.platforms.count == 1
        {
            buildPlatform = resolvedPlatform
        } else {
            throw TestServiceError.unspecifiedPlatform(
                target: buildableTarget.target.name,
                platforms: buildableTarget.target.supportedPlatforms.map(\.rawValue)
            )
        }

        let destination: XcodeBuildDestination?

        if passthroughXcodeBuildArguments.contains("-destination") {
            destination = nil
        } else {
            destination = try await XcodeBuildDestination.find(
                for: buildableTarget.target,
                on: buildPlatform,
                scheme: scheme,
                version: version,
                deviceName: deviceName,
                graphTraverser: graphTraverser,
                simulatorController: simulatorController
            )
        }

        let passthroughDerivedDataPath = try? await xcodeBuildAgumentParser
            .parse(passthroughXcodeBuildArguments)
            .derivedDataPath
        let projectDerivedDataDirectory: AbsolutePath?
        if let derivedDataPath {
            projectDerivedDataDirectory = derivedDataPath
        } else if let passthroughDerivedDataPath {
            projectDerivedDataDirectory = passthroughDerivedDataPath
        } else {
            projectDerivedDataDirectory = try? await derivedDataLocator.locate(
                for: graphTraverser.workspace.xcWorkspacePath
            )
        }

        do {
            try await xcodebuildController.test(
                .workspace(graphTraverser.workspace.xcWorkspacePath),
                scheme: scheme.name,
                clean: clean,
                destination: destination,
                action: action,
                rosetta: rosetta,
                derivedDataPath: derivedDataPath,
                resultBundlePath: resultBundlePath,
                arguments: buildGraphInspector.buildArguments(
                    project: buildableTarget.project,
                    target: buildableTarget.target,
                    configuration: configuration,
                    skipSigning: false
                ),
                retryCount: retryCount,
                testTargets: testTargets,
                skipTestTargets: skipTestTargets,
                testPlanConfiguration: testPlanConfiguration,
                passthroughXcodeBuildArguments: passthroughXcodeBuildArguments
            )
        } catch {
            await uploadBuildRunIfNeeded(
                projectDerivedDataDirectory: projectDerivedDataDirectory,
                projectPath: graphTraverser.workspace.xcWorkspacePath,
                config: config,
                scheme: scheme.name,
                configuration: configuration ?? scheme.testAction?.configurationName
            )
            let summary = mode == .local
                ? await testSummary(resultBundlePath: resultBundlePath, quarantinedTests: quarantinedTests)
                : nil
            await uploadResultBundleIfNeeded(
                testSummary: summary,
                resultBundlePath: resultBundlePath,
                projectDerivedDataDirectory: projectDerivedDataDirectory,
                config: config,
                action: action,
                scheme: scheme.name,
                quarantinedTests: quarantinedTests,
                mode: mode
            )
            throw error
        }

        await uploadBuildRunIfNeeded(
            projectDerivedDataDirectory: projectDerivedDataDirectory,
            projectPath: graphTraverser.workspace.xcWorkspacePath,
            config: config,
            scheme: scheme.name,
            configuration: configuration ?? scheme.testAction?.configurationName
        )
        let summary = mode == .local
            ? await testSummary(resultBundlePath: resultBundlePath, quarantinedTests: quarantinedTests)
            : nil
        await uploadResultBundleIfNeeded(
            testSummary: summary,
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: projectDerivedDataDirectory,
            config: config,
            action: action,
            quarantinedTests: quarantinedTests,
            mode: mode
        )
    }

    private func testSummary(
        resultBundlePath: AbsolutePath?,
        quarantinedTests: [TestIdentifier]
    ) async -> TestSummary? {
        guard let resultBundlePath,
              let rootDir = try? await rootDirectory(),
              let parsed = try? await xcResultService.parse(path: resultBundlePath, rootDirectory: rootDir)
        else { return nil }
        return testQuarantineService.markQuarantinedTests(testSummary: parsed, quarantinedTests: quarantinedTests)
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

    private func uploadBuildRunIfNeeded(
        projectDerivedDataDirectory: AbsolutePath?,
        projectPath: AbsolutePath,
        config: Tuist,
        scheme: String?,
        configuration: String?
    ) async {
        guard config.fullHandle != nil,
              let projectDerivedDataDirectory,
              let mostRecentActivityLogFile = try? await xcActivityLogController.mostRecentActivityLogFile(
                  projectDerivedDataDirectory: projectDerivedDataDirectory
              )
        else { return }

        await RunMetadataStorage.current.update(buildRunId: mostRecentActivityLogFile.path.basenameWithoutExt)

        guard let uploadBuildRunService else { return }
        do {
            try await uploadBuildRunService.uploadBuildRun(
                activityLogPath: mostRecentActivityLogFile.path,
                projectPath: projectPath,
                config: config,
                scheme: scheme,
                configuration: configuration
            )
        } catch {
            AlertController.current.warning(.alert("Failed to upload build: \(error.localizedDescription)"))
        }
    }

    private func uploadResultBundleIfNeeded(
        testSummary: TestSummary?,
        resultBundlePath: AbsolutePath?,
        projectDerivedDataDirectory: AbsolutePath?,
        config: Tuist,
        action: XcodeBuildTestAction,
        scheme: String? = nil,
        quarantinedTests: [TestIdentifier] = [],
        shardPlanId: String? = nil,
        shardIndex: Int? = nil,
        mode: TestProcessingMode = .local
    ) async {
        guard config.fullHandle != nil, action != .build
        else { return }

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

    private func destination(
        arguments: [String],
        deviceName: String?,
        osVersion: String?
    ) async throws -> SimulatorDeviceAndRuntime? {
        if let deviceName {
            let os: XcodeGraph.Version?
            if let osVersion {
                os = XcodeGraph.Version(string: osVersion)
            } else {
                os = nil
            }
            return try await simulatorController.findAvailableDevice(
                deviceName: deviceName,
                version: os.map { TSCUtility.Version($0.major, $0.minor, $0.patch) }
            )
        }
        let parsedArguments =
            try await xcodeBuildAgumentParser
                .parse(arguments)
        if let destination = parsedArguments.destination {
            if let id = destination.id {
                return try await simulatorController.findAvailableDevice(udid: id)
            } else if let name = destination.name {
                return try await simulatorController.findAvailableDevice(
                    deviceName: name,
                    version: destination.os.map { TSCUtility.Version($0.major, $0.minor, $0.patch) }
                )
            }
        }

        return nil
    }

    private func rootDirectory() async throws -> AbsolutePath? {
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let workingDirectory = Environment.current.workspacePath ?? currentWorkingDirectory
        if await gitController.isInGitRepository(workingDirectory: workingDirectory) {
            return try await gitController.topLevelGitDirectory(workingDirectory: workingDirectory)
        } else {
            return try await rootDirectoryLocator.locate(from: workingDirectory)
        }
    }

    private func uploadSkippedTestSummary(
        schemeName: String?,
        config: Tuist,
        timer: any ClockTimer
    ) async throws {
        guard let fullHandle = config.fullHandle else { return }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        let rootDirectory = try await rootDirectory()
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let gitInfoDirectory = rootDirectory ?? currentWorkingDirectory

        let durationInMs = Int(timer.stop() * 1000)

        let testSummary = TestSummary(
            testPlanName: schemeName,
            status: .passed,
            duration: durationInMs,
            testModules: []
        )

        let gitInfo = try await gitController.gitInfo(workingDirectory: gitInfoDirectory)
        let ciInfo = ciController.ciInfo()
        let buildRunId = await RunMetadataStorage.current.buildRunId

        let test = try await createTestService.createTest(
            fullHandle: fullHandle,
            serverURL: serverURL,
            id: nil,
            testSummary: testSummary,
            buildRunId: buildRunId,
            gitBranch: gitInfo.branch,
            gitCommitSHA: gitInfo.sha,
            gitRef: gitInfo.ref,
            gitRemoteURLOrigin: gitInfo.remoteURLOrigin,
            isCI: Environment.current.isCI,
            modelIdentifier: machineEnvironment.modelIdentifier(),
            macOSVersion: machineEnvironment.macOSVersion,
            xcodeVersion: try await xcodebuildController.version()?.description,
            ciRunId: ciInfo?.runId,
            ciProjectHandle: ciInfo?.projectHandle,
            ciHost: ciInfo?.host,
            ciProvider: ciInfo?.provider,
            shardPlanId: nil,
            shardIndex: nil
        )

        await RunMetadataStorage.current.update(testRunId: test.id)
    }

    private func passedValue(for option: String, arguments: [String]) -> String? {
        guard let optionIndex = arguments.firstIndex(of: option) else { return nil }
        let valueIndex = arguments.index(after: optionIndex)
        guard arguments.endIndex > valueIndex else { return nil }
        return arguments[valueIndex]
    }

    func inferPlatformDestination(
        schemes: [Scheme],
        testPlan: String? = nil,
        graphTraverser: GraphTraversing
    ) -> String? {
        for scheme in schemes {
            guard let target = buildGraphInspector.testableTarget(
                scheme: scheme,
                testPlan: testPlan,
                testTargets: [],
                skipTestTargets: [],
                graphTraverser: graphTraverser,
                action: .build
            ) else { continue }

            guard let resolvedPlatform = target.target.destinations.first?.platform,
                  target.target.destinations.platforms.count == 1
            else { continue }

            return resolvedPlatform.xcodebuildPlatformDestination
        }
        return nil
    }

    private func xcodebuildDestination(
        for target: GraphTarget,
        scheme: Scheme,
        platform: XcodeGraph.Platform,
        version: Version?,
        deviceName: String?,
        graphTraverser: GraphTraversing
    ) async throws -> String {
        let destination = try await XcodeBuildDestination.find(
            for: target.target,
            on: platform,
            scheme: scheme,
            version: version,
            deviceName: deviceName,
            graphTraverser: graphTraverser,
            simulatorController: simulatorController
        )

        switch destination {
        case let .device(udid):
            return "\(platform.xcodebuildPlatformDestination),id=\(udid)"
        case .mac:
            return try await simulatorController.macOSDestination(catalyst: false)
        case .macCatalyst:
            return try await simulatorController.macOSDestination(catalyst: true)
        }
    }

    private func simulatorPlatform(from destination: String) -> XcodeGraph.Platform? {
        guard let platform = xcodebuildPlatform(from: destination), platform != .macOS else { return nil }
        return platform
    }

    private func xcodebuildPlatform(from destination: String) -> XcodeGraph.Platform? {
        switch xcodebuildDestinationParameter("platform", in: destination)?.lowercased() {
        case "ios simulator":
            return .iOS
        case "macos":
            return .macOS
        case "tvos simulator":
            return .tvOS
        case "watchos simulator":
            return .watchOS
        case "visionos simulator":
            return .visionOS
        default:
            return nil
        }
    }

    private func hasConcreteDevice(in destination: String) -> Bool {
        xcodebuildDestinationParameter("id", in: destination) != nil
            || xcodebuildDestinationParameter("name", in: destination) != nil
    }

    private func xcodebuildDestinationParameter(_ parameter: String, in destination: String) -> String? {
        let expectedKey = parameter.lowercased()
        for component in destination.components(separatedBy: ",") {
            let pair = component.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            guard pair.count == 2 else { continue }

            let key = pair[0].lowercased()
            if key == expectedKey {
                return pair[1]
            }
        }

        return nil
    }
}

extension XcodeGraph.Platform {
    var xcodebuildPlatformDestination: String {
        switch self {
        case .iOS: "platform=iOS Simulator"
        case .macOS: "platform=macOS"
        case .tvOS: "platform=tvOS Simulator"
        case .watchOS: "platform=watchOS Simulator"
        case .visionOS: "platform=visionOS Simulator"
        }
    }
}
