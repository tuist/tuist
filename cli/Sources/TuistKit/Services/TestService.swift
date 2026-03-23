import FileSystem
import Foundation
import Path
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
import TuistXCResultService
import XcodeGraph

import struct TSCUtility.Version

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
        }
    }

    // Error type

    public var type: ErrorType {
        switch self {
        case .schemeNotFound, .schemeWithoutTestableTargets, .testPlanNotFound,
             .testIdentifierInvalid, .duplicatedTestTargets,
             .nothingToSkip, .actionInvalid, .testProductsNotFound, .unspecifiedPlatform:
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
    private let inspectResultBundleService: InspectResultBundleServicing
    private let derivedDataLocator: DerivedDataLocating
    private let createTestService: CreateTestServicing
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let ciController: CIControlling
    private let clock: Clock
    private let listTestCasesService: ListTestCasesServicing
    private let shardPlanService: ShardPlanServicing
    private let shardService: ShardServicing

    public init(
        generatorFactory: GeneratorFactorying,
        cacheStorageFactory: CacheStorageFactorying
    ) {
        let manifestLoader = ManifestLoader.current
        let configLoader = ConfigLoader()
        self.init(
            generatorFactory: generatorFactory,
            cacheStorageFactory: cacheStorageFactory,
            configLoader: configLoader,
            listTestCasesService: ListTestCasesService()
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
        inspectResultBundleService: InspectResultBundleServicing = InspectResultBundleService(),
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
        createTestService: CreateTestServicing = CreateTestService(),
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        ciController: CIControlling = CIController(),
        clock: Clock = WallClock(),
        listTestCasesService: ListTestCasesServicing = ListTestCasesService(),
        shardPlanService: ShardPlanServicing = ShardPlanService(),
        shardService: ShardServicing = ShardService()
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
        self.inspectResultBundleService = inspectResultBundleService
        self.derivedDataLocator = derivedDataLocator
        self.createTestService = createTestService
        self.machineEnvironment = machineEnvironment
        self.serverEnvironmentService = serverEnvironmentService
        self.ciController = ciController
        self.clock = clock
        self.listTestCasesService = listTestCasesService
        self.shardPlanService = shardPlanService
        self.shardService = shardService
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
        shardIndex: Int? = nil
    ) async throws {
        if validateTestTargetsParameters {
            try Self.validateParameters(
                testTargets: testTargets,
                skipTestTargets: skipTestTargets
            )
        }
        // Load config
        let config = try await configLoader.loadConfig(path: path)
            .assertingIsGeneratedProjectOrSwiftPackage(
                errorMessageOverride:
                "The 'tuist test' command is for generated projects or Swift packages. Please use 'tuist xcodebuild test' instead."
            )

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
                runId: runId
            )
            return
        }

        if action == .testWithoutBuilding,
           let testProductsPath = testProductsPathFromArguments(passthroughXcodeBuildArguments)
        {
            let selectiveTestingGraphPath = testProductsPath.appending(component: SelectiveTestingGraph.fileName)
            if try await fileSystem.exists(selectiveTestingGraphPath) {
                try await runTestWithoutBuildingFromBundle(
                    testProductsPath: testProductsPath,
                    selectiveTestingGraphPath: selectiveTestingGraphPath,
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
                    runId: runId
                )
                return
            }
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
            destination: destination
        )

        Logger.current.notice("Generating project for testing", metadata: .section)
        let (_, graph, mapperEnvironment) = try await testGenerator.generateWithGraph(
            path: path,
            options: config.project.generatedProject?.generationOptions
        )

        if generateOnly {
            return
        }

        var skipTestTargets = skipTestTargets
        skipTestTargets.append(
            contentsOf: await quarantinedTestsToSkip(
                skipQuarantine: skipQuarantine,
                config: config
            )
        )

        let graphTraverser = GraphTraverser(graph: graph)
        let version = osVersion?.version()
        let testableSchemes =
            buildGraphInspector.testableSchemes(graphTraverser: graphTraverser)
                + buildGraphInspector.workspaceSchemes(graphTraverser: graphTraverser)
        Logger.current.log(
            level: .debug,
            "Found the following testable schemes: \(Set(testableSchemes.map(\.name)).joined(separator: ", "))"
        )

        let derivedDataPath = try derivedDataPath.map {
            try AbsolutePath(
                validating: $0,
                relativeTo: FileHandler.shared.currentPath
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
                return
            case (_?, _, true), (_?, _, nil):
                Logger.current.log(
                    level: .info,
                    "The scheme \(schemeName)'s test action has no test plans to run, finishing early."
                )
                return
            default:
                break
            }

            schemes = [scheme]
        } else {
            schemes = buildGraphInspector.workspaceSchemes(graphTraverser: graphTraverser)
            await updateTestServiceAnalytics(
                mapperEnvironment: mapperEnvironment,
                schemes: schemes,
                testPlanConfiguration: testPlanConfiguration,
                action: action
            )
        }

        var passthroughXcodeBuildArguments = passthroughXcodeBuildArguments

        if shardMin != nil || shardMax != nil || shardTotal != nil, action == .build,
           !passthroughXcodeBuildArguments.contains("-testProductsPath")
        {
            let testProductsDir = try await fileSystem.makeTemporaryDirectory(prefix: "shard-test-products")
            let productsPath = testProductsDir.appending(component: "TestProducts.xctestproducts")
            passthroughXcodeBuildArguments += ["-testProductsPath", productsPath.pathString]
        }

        let schemeTestTargetNames = Set(
            schemes.flatMap {
                testActionTargetReferences(
                    scheme: $0,
                    testPlanConfiguration: testPlanConfiguration,
                    action: action
                )
            }.map(\.name)
        )
        let testTargets = testTargets.filter { schemeTestTargetNames.contains($0.target) }

        do {
            try await testSchemes(
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
                config: config
            )
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
                derivedDataPath: derivedDataPath
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

                if shardMin != nil || shardMax != nil || shardTotal != nil,
                   let fullHandle = config.fullHandle
                {
                    let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
                    _ = try await shardPlanService.plan(
                        xctestproductsPath: testProductsPath,
                        schemes: schemes.map(\.name),
                        reference: shardReference,
                        shardGranularity: shardGranularity,
                        shardMin: shardMin,
                        shardMax: shardMax,
                        shardTotal: shardTotal,
                        shardMaxDuration: shardMaxDuration,
                        fullHandle: fullHandle,
                        serverURL: serverURL
                    )
                }
            }
        }
    }

    // MARK: - Shard Execute

    // swiftlint:disable:next function_body_length function_parameter_count
    private func runShard(
        shardIndex: Int,
        schemeName _: String?,
        path _: AbsolutePath,
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
        runId: String
    ) async throws {
        guard let fullHandle = config.fullHandle else {
            throw TestServiceError.actionInvalid
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        let shard = try await shardService.shard(
            shardIndex: shardIndex,
            fullHandle: fullHandle,
            serverURL: serverURL
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

        let derivedDataPath = try derivedDataPath.map {
            try AbsolutePath(
                validating: $0,
                relativeTo: FileHandler.shared.currentPath
            )
        }

        let xcodebuildArguments = try await buildTestWithoutBuildingArguments(
            testProductsPath: shard.testProductsPath,
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

        var testError: Error?

        do {
            try await xcodebuildController.run(arguments: xcodebuildArguments)
        } catch {
            testError = error
        }

        await inspectResultBundleIfNeeded(
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: derivedDataPath,
            config: config,
            action: .testWithoutBuilding,
            shardPlanId: shard.shardPlanId,
            shardIndex: shardIndex
        )

        if let selectiveTestingGraph = shard.selectiveTestingGraph {
            try await storeSuccessfulShardTestHashes(
                selectiveTestingGraph: selectiveTestingGraph,
                passingTargetNames: await passingTargetNames(resultBundlePath: resultBundlePath),
                cacheStorage: cacheStorage
            )
        }

        try await copyResultBundlePathIfNeeded(
            runResultBundlePath: runResultBundlePath,
            resultBundlePath: resultBundlePath
        )
        try? await fileSystem.remove(shard.testProductsPath)

        if let testError {
            throw testError
        }

        AlertController.current.success(.alert("The project tests ran successfully"))
    }

    // MARK: - Test Without Building (from bundle)

    // swiftlint:disable:next function_body_length function_parameter_count
    private func runTestWithoutBuildingFromBundle(
        testProductsPath: AbsolutePath,
        selectiveTestingGraphPath: AbsolutePath,
        config: Tuist,
        deviceName: String?,
        platform: String?,
        osVersion: String?,
        rosetta: Bool,
        resultBundlePath: AbsolutePath?,
        derivedDataPath: String?,
        retryCount: Int,
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier],
        testPlanConfiguration: TestPlanConfiguration?,
        passthroughXcodeBuildArguments: [String],
        runId: String
    ) async throws {
        Logger.current.notice(
            "Skipping project generation — using selective testing graph from .xctestproducts bundle",
            metadata: .section
        )

        let selectiveTestingGraph: SelectiveTestingGraph = try await fileSystem.readJSONFile(
            at: selectiveTestingGraphPath
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

        let derivedDataPath = try derivedDataPath.map {
            try AbsolutePath(
                validating: $0,
                relativeTo: FileHandler.shared.currentPath
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

        var testError: Error?

        do {
            try await xcodebuildController.run(arguments: xcodebuildArguments)
        } catch {
            testError = error
        }

        await inspectResultBundleIfNeeded(
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: derivedDataPath,
            config: config,
            action: .testWithoutBuilding
        )

        try await storeSuccessfulShardTestHashes(
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

    private func testProductsPathFromArguments(_ arguments: [String]) -> AbsolutePath? {
        guard let index = arguments.firstIndex(of: "-testProductsPath"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return try? AbsolutePath(validating: arguments[index + 1])
    }

    private func buildTestWithoutBuildingArguments(
        testProductsPath: AbsolutePath,
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier],
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
        arguments += ["-testProductsPath", testProductsPath.pathString]

        for testTarget in testTargets {
            arguments += ["-only-testing", testTarget.description]
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
                switch buildPlatform {
                case .iOS:
                    arguments += ["-destination", "platform=iOS Simulator,name=iPhone"]
                case .macOS:
                    arguments += ["-destination", "platform=macOS"]
                case .tvOS:
                    arguments += ["-destination", "platform=tvOS Simulator,name=Apple TV"]
                case .watchOS:
                    arguments += ["-destination", "platform=watchOS Simulator,name=Apple Watch"]
                case .visionOS:
                    arguments += ["-destination", "platform=visionOS Simulator,name=Apple Vision Pro"]
                }
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
        derivedDataPath: AbsolutePath?
    ) async throws -> AbsolutePath {
        if let index = passthroughXcodeBuildArguments.firstIndex(of: "-testProductsPath"),
           passthroughXcodeBuildArguments.indices.contains(index + 1)
        {
            return try AbsolutePath(validating: passthroughXcodeBuildArguments[index + 1])
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
            return SelectiveTestingGraph(testTargetHashes: [:])
        }

        let graphTraverser = GraphTraverser(graph: initialGraph)
        let initialSchemes = graphTraverser.schemes()
        let matchingSchemes = initialSchemes.filter { initialScheme in
            schemes.contains(where: { $0.name == initialScheme.name })
        }
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

        return SelectiveTestingGraph(testTargetHashes: testTargetHashes)
    }

    private func storeSuccessfulShardTestHashes(
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
        config: Tuist
    ) async throws {
        let timer = clock.startTimer()
        let graphTraverser = GraphTraverser(graph: graph)
        let testSchemes =
            schemes
                .filter {
                    !testActionTargetReferences(
                        scheme: $0, testPlanConfiguration: testPlanConfiguration,
                        action: action
                    ).isEmpty
                }

        if !shouldRunTest(
            for: schemes,
            testPlanConfiguration: testPlanConfiguration,
            mapperEnvironment: mapperEnvironment,
            graph: graph,
            action: action
        ) {
            if action != .build {
                try await uploadSkippedTestSummary(
                    schemeName: schemes.first?.name,
                    config: config,
                    timer: timer
                )
            }
            return
        }

        let uploadCacheStorage: CacheStoring
        if noUpload {
            uploadCacheStorage = try await cacheStorageFactory.cacheLocalStorage()
        } else {
            uploadCacheStorage = cacheStorage
        }

        do {
            for testScheme in testSchemes {
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
                    derivedDataPath: derivedDataPath,
                    retryCount: retryCount,
                    testTargets: testTargets,
                    skipTestTargets: skipTestTargets,
                    testPlanConfiguration: testPlanConfiguration,
                    passthroughXcodeBuildArguments: passthroughXcodeBuildArguments,
                    config: config
                )
            }
        } catch {
            // Check the test results and store successful test hashes for any targets that passed
            let rootDirectory = try await rootDirectory()
            guard action != .build, let resultBundlePath,
                  let testSummary = try await xcResultService.parse(path: resultBundlePath, rootDirectory: rootDirectory)
            else { throw error }

            let testTargets = testActionTargets(
                for: schemes, testPlanConfiguration: testPlanConfiguration, graph: graph, action: action
            )

            // Compute passing test target names from the test summary
            // A target is passing if none of its tests failed
            let testCasesByModule = Dictionary(grouping: testSummary.testCases) { $0.module }
            let passingTestTargetNames = Set(
                testCasesByModule.compactMap { module, testCases -> String? in
                    guard let module else { return nil }
                    return testCases.allSatisfy { $0.status != .failed } ? module : nil
                }
            )
            let passingTestTargets = testTargets.filter {
                passingTestTargetNames.contains($0.target.name)
            }

            try await storeSuccessfulTestHashes(
                for: passingTestTargets,
                graph: graph,
                mapperEnvironment: mapperEnvironment,
                cacheStorage: uploadCacheStorage
            )

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

        AlertController.current.success(.alert("The project tests \(verb) successfully"))
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

    private func shouldRunTest(
        for schemes: [Scheme],
        testPlanConfiguration: TestPlanConfiguration?,
        mapperEnvironment: MapperEnvironment,
        graph: Graph,
        action: XcodeBuildTestAction
    ) -> Bool {
        let testActionTargets = testActionTargets(
            for: schemes,
            testPlanConfiguration: testPlanConfiguration,
            graph: graph,
            action: action
        )
        .map(\.target)

        let skippedTestTargets = initialTestTargets(
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

        let testSchemes =
            schemes
                .filter {
                    !testActionTargetReferences(
                        scheme: $0, testPlanConfiguration: testPlanConfiguration, action: action
                    ).isEmpty
                }

        if testSchemes.isEmpty {
            Logger.current.log(level: .info, "There are no tests to run, finishing early")
            return false
        }

        if !skippedTestTargets.isEmpty {
            Logger.current
                .notice(
                    "The following targets have not changed since the last successful run and will be skipped: \(skippedTestTargets.map(\.target.name).sorted().joined(separator: ", "))"
                )
        }

        let testedTargetNames = testActionTargets.map(\.name).sorted()
        if !testedTargetNames.isEmpty {
            Logger.current
                .notice(
                    "Testing the following targets: \(testedTargetNames.joined(separator: ", "))"
                )
        }

        return true
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
        let targets =
            if let testPlanConfiguration {
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

        return targets
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
        config: Tuist
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

        let projectDerivedDataDirectory: AbsolutePath?
        if let derivedDataPath {
            projectDerivedDataDirectory = derivedDataPath
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
            await inspectResultBundleIfNeeded(
                resultBundlePath: resultBundlePath,
                projectDerivedDataDirectory: projectDerivedDataDirectory,
                config: config,
                action: action
            )
            throw error
        }

        await inspectResultBundleIfNeeded(
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: projectDerivedDataDirectory,
            config: config,
            action: action
        )
    }

    private func inspectResultBundleIfNeeded(
        resultBundlePath: AbsolutePath?,
        projectDerivedDataDirectory: AbsolutePath?,
        config: Tuist,
        action: XcodeBuildTestAction,
        shardPlanId: String? = nil,
        shardIndex: Int? = nil
    ) async {
        guard let resultBundlePath, config.fullHandle != nil, action != .build,
              (try? await fileSystem.exists(resultBundlePath)) == true
        else { return }

        do {
            _ = try await inspectResultBundleService.inspectResultBundle(
                resultBundlePath: resultBundlePath,
                projectDerivedDataDirectory: projectDerivedDataDirectory,
                config: config,
                shardPlanId: shardPlanId,
                shardIndex: shardIndex
            )
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
        if gitController.isInGitRepository(workingDirectory: workingDirectory) {
            return try gitController.topLevelGitDirectory(workingDirectory: workingDirectory)
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

        let gitInfo = try gitController.gitInfo(workingDirectory: gitInfoDirectory)
        let ciInfo = ciController.ciInfo()

        let test = try await createTestService.createTest(
            fullHandle: fullHandle,
            serverURL: serverURL,
            testSummary: testSummary,
            buildRunId: nil,
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

    private func quarantinedTestsToSkip(
        skipQuarantine: Bool,
        config: Tuist
    ) async -> [TestIdentifier] {
        Logger.current.log(
            level: .debug,
            "Quarantine check: skipQuarantine=\(skipQuarantine), fullHandle=\(config.fullHandle ?? "nil")"
        )
        guard !skipQuarantine, let fullHandle = config.fullHandle else {
            return []
        }
        do {
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
            let quarantinedTests = try await fetchQuarantinedTests(
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            Logger.current.log(
                level: .debug,
                "Fetched \(quarantinedTests.count) quarantined test(s)"
            )
            if !quarantinedTests.isEmpty {
                Logger.current.notice(
                    "Skipping \(quarantinedTests.count) quarantined test(s)",
                    metadata: .subsection
                )
            }
            return quarantinedTests
        } catch {
            Logger.current.log(
                level: .warning,
                "Failed to fetch quarantined tests: \(error.localizedDescription). Running all tests."
            )
            AlertController.current.warning(
                .alert("Failed to fetch quarantined tests: \(error.localizedDescription). Running all tests.")
            )
            return []
        }
    }

    private func fetchQuarantinedTests(
        fullHandle: String,
        serverURL: URL
    ) async throws -> [TestIdentifier] {
        let response = try await listTestCasesService.listTestCases(
            fullHandle: fullHandle,
            serverURL: serverURL,
            flaky: nil,
            quarantined: true,
            page: 1,
            pageSize: 500
        )

        return try response.test_cases.map { testCase in
            try TestIdentifier(
                target: testCase.module.name,
                class: testCase.suite?.name,
                method: testCase.name
            )
        }
    }
}
