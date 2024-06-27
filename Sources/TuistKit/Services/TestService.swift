import Foundation
import Path
import struct TSCUtility.Version
import TuistAutomation
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XcodeGraph

enum TestServiceError: FatalError, Equatable {
    case schemeNotFound(scheme: String, existing: [String])
    case schemeWithoutTestableTargets(scheme: String, testPlan: String?)
    case testPlanNotFound(scheme: String, testPlan: String, existing: [String])
    case testIdentifierInvalid(value: String)
    case duplicatedTestTargets(Set<TestIdentifier>)
    case nothingToSkip(skipped: [TestIdentifier], included: [TestIdentifier])

    // Error description
    var description: String {
        switch self {
        case let .schemeNotFound(scheme, existing):
            return "Couldn't find scheme \(scheme). The available schemes are: \(existing.joined(separator: ", "))."
        case let .schemeWithoutTestableTargets(scheme, testPlan):
            let testPlanMessage: String
            if let testPlan, !testPlan.isEmpty {
                testPlanMessage = "test plan \(testPlan) in "
            } else {
                testPlanMessage = ""
            }
            return "The \(testPlanMessage)scheme \(scheme) cannot be built because it contains no buildable targets."
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
            return "Invalid test identifiers \(value). The expected format is TestTarget[/TestClass[/TestMethod]]."
        case let .duplicatedTestTargets(targets):
            return "The target identifier cannot be specified both in --test-targets and --skip-test-targets (were specified: \(targets.map(\.description).joined(separator: ", ")))"
        case let .nothingToSkip(skippedTargets, includedTargets):
            return "Some of the targets specified in --skip-test-targets (\(skippedTargets.map(\.description).joined(separator: ", "))) will always be skipped as they are not included in the targets specified (\(includedTargets.map(\.description).joined(separator: ", ")))"
        }
    }

    // Error type
    var type: ErrorType {
        switch self {
        case .schemeNotFound, .schemeWithoutTestableTargets, .testPlanNotFound, .testIdentifierInvalid, .duplicatedTestTargets,
             .nothingToSkip:
            return .abort
        }
    }
}

final class TestService { // swiftlint:disable:this type_body_length
    private let generatorFactory: GeneratorFactorying
    private let cacheStorageFactory: CacheStorageFactorying
    private let xcodebuildController: XcodeBuildControlling
    private let buildGraphInspector: BuildGraphInspecting
    private let simulatorController: SimulatorControlling
    private let contentHasher: ContentHashing
    private let automationStorage: AutomationStoring

    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring
    private let configLoader: ConfigLoading

    public convenience init(
        generatorFactory: GeneratorFactorying,
        cacheStorageFactory: CacheStorageFactorying
    ) {
        let manifestLoaderFactory = ManifestLoaderFactory()
        let manifestLoader = manifestLoaderFactory.createManifestLoader()
        let configLoader = ConfigLoader(manifestLoader: manifestLoader)
        self.init(
            generatorFactory: generatorFactory,
            cacheStorageFactory: cacheStorageFactory,
            configLoader: configLoader,
            automationStorage: AutomationStorage()
        )
    }

    init(
        generatorFactory: GeneratorFactorying = GeneratorFactory(),
        cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory(),
        xcodebuildController: XcodeBuildControlling = XcodeBuildController(),
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        simulatorController: SimulatorControlling = SimulatorController(),
        contentHasher: ContentHashing = ContentHasher(),
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring = CacheDirectoriesProviderFactory(),
        configLoader: ConfigLoading,
        automationStorage: AutomationStoring
    ) {
        self.generatorFactory = generatorFactory
        self.cacheStorageFactory = cacheStorageFactory
        self.xcodebuildController = xcodebuildController
        self.buildGraphInspector = buildGraphInspector
        self.simulatorController = simulatorController
        self.contentHasher = contentHasher
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
        self.configLoader = configLoader
        self.automationStorage = automationStorage
    }

    static func validateParameters(
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier]
    ) throws {
        let targetsIntersection = Set(testTargets)
            .intersection(skipTestTargets)
        if !targetsIntersection.isEmpty {
            throw TestServiceError.duplicatedTestTargets(targetsIntersection)
        }
        if !testTargets.isEmpty {
            // --test-targets Test --skip-test-targets AnotherTest
            let skipTestTargetsOnly = try Set(skipTestTargets.map { try TestIdentifier(target: $0.target) })
            let testTargetsOnly = try testTargets.map { try TestIdentifier(target: $0.target) }
            let targetsOnlyIntersection = skipTestTargetsOnly.intersection(testTargetsOnly)
            if !skipTestTargets.isEmpty, targetsOnlyIntersection.isEmpty {
                throw TestServiceError.nothingToSkip(
                    skipped: try skipTestTargets
                        .filter { skipTarget in try !testTargetsOnly.contains(TestIdentifier(target: skipTarget.target)) },
                    included: testTargets
                )
            }

            // --test-targets Test/MyClass --skip-test-targets Test/AnotherClass
            let skipTestTargetsClasses = try Set(skipTestTargets.map { try TestIdentifier(target: $0.target, class: $0.class) })
            let testTargetsClasses = try testTargets.lazy.filter { $0.class != nil }
                .map { try TestIdentifier(target: $0.target, class: $0.class) }
            let targetsClassesIntersection = skipTestTargetsClasses.intersection(testTargetsClasses)
            if !testTargetsClasses.isEmpty, !skipTestTargetsClasses.isEmpty, targetsClassesIntersection.isEmpty {
                throw TestServiceError.nothingToSkip(
                    skipped: try skipTestTargets
                        .filter { skipTarget in
                            try !testTargetsClasses
                                .contains { try $0 == TestIdentifier(target: skipTarget.target, class: skipTarget.class) }
                        },
                    included: testTargets
                )
            }

            // --test-targets Test/MyClass/MyMethod --skip-test-targets Test/MyClass/AnotherMethod
            let skipTestTargetsClassesMethods = Set(skipTestTargets)
            let testTargetsClassesMethods = testTargets.lazy.filter { $0.class != nil && $0.method != nil }
            let targetsClassesMethodsIntersection = skipTestTargetsClassesMethods.intersection(testTargetsClasses)
            if !testTargetsClassesMethods.isEmpty, targetsClassesMethodsIntersection.isEmpty,
               !skipTestTargetsClassesMethods.isEmpty
            {
                throw TestServiceError.nothingToSkip(skipped: skipTestTargets, included: testTargets)
            }
        }
    }

    // swiftlint:disable:next function_body_length
    func run(
        runId: String,
        schemeName: String?,
        clean: Bool,
        configuration: String?,
        path: AbsolutePath,
        deviceName: String?,
        platform: String?,
        osVersion: String?,
        rosetta: Bool,
        skipUITests: Bool,
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
        passthroughXcodeBuildArguments: [String]
    ) async throws {
        if validateTestTargetsParameters {
            try Self.validateParameters(
                testTargets: testTargets,
                skipTestTargets: skipTestTargets
            )
        }
        // Load config
        let config = try configLoader.loadConfig(path: path)
        let cacheStorage = try cacheStorageFactory.cacheStorage(config: config)

        let testsCacheTemporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)

        let testGenerator = generatorFactory.testing(
            config: config,
            testsCacheDirectory: testsCacheTemporaryDirectory.path,
            testPlan: testPlanConfiguration?.testPlan,
            includedTargets: Set(testTargets.map(\.target)),
            excludedTargets: Set(skipTestTargets.filter { $0.class == nil }.map(\.target)),
            skipUITests: skipUITests,
            configuration: configuration,
            ignoreBinaryCache: ignoreBinaryCache,
            ignoreSelectiveTesting: ignoreSelectiveTesting,
            cacheStorage: cacheStorage,
            automationStorage: automationStorage
        )

        logger.notice("Generating project for testing", metadata: .section)
        let graph = try await testGenerator.generateWithGraph(
            path: path
        ).1

        if generateOnly {
            return
        }

        let graphTraverser = GraphTraverser(graph: graph)
        let version = osVersion?.version()
        let testableSchemes = buildGraphInspector.testableSchemes(graphTraverser: graphTraverser) +
            buildGraphInspector.workspaceSchemes(graphTraverser: graphTraverser)
        logger.log(
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

        let resultBundlePath = try self.resultBundlePath(
            passedResultBundlePath: passedResultBundlePath,
            runId: runId,
            config: config
        )

        defer {
            if let resultBundlePath, let passedResultBundlePath, config.cloud != nil {
                if !FileHandler.shared.exists(resultBundlePath.parentDirectory) {
                    try? FileHandler.shared.createFolder(resultBundlePath.parentDirectory)
                }
                try? FileHandler.shared.copy(from: passedResultBundlePath, to: resultBundlePath)
            }
        }

        if let schemeName {
            guard let scheme = graphTraverser.schemes().first(where: { $0.name == schemeName })
            else {
                let schemes = automationStorage.initialGraph.map(GraphTraverser.init)?.schemes() ?? graphTraverser.schemes()
                if schemes.first(where: { $0.name == schemeName }) != nil {
                    logger.log(level: .info, "The scheme \(schemeName)'s test action has no tests to run, finishing early.")
                    return
                } else {
                    throw TestServiceError.schemeNotFound(
                        scheme: schemeName,
                        existing: Set(schemes.map(\.name)).map { $0 }
                    )
                }
            }

            switch (testPlanConfiguration?.testPlan, scheme.testAction?.targets.isEmpty, scheme.testAction?.testPlans?.isEmpty) {
            case (_, false, _):
                break
            case (nil, true, _), (nil, nil, _):
                logger.log(level: .info, "The scheme \(schemeName)'s test action has no tests to run, finishing early.")
                return
            case (_?, _, true), (_?, _, nil):
                logger.log(level: .info, "The scheme \(schemeName)'s test action has no test plans to run, finishing early.")
                return
            default:
                break
            }

            let testSchemes: [Scheme] = [scheme]

            for testScheme in testSchemes {
                try await self.testScheme(
                    scheme: testScheme,
                    graphTraverser: graphTraverser,
                    clean: clean,
                    configuration: configuration,
                    version: version,
                    deviceName: deviceName,
                    platform: platform,
                    rosetta: rosetta,
                    resultBundlePath: resultBundlePath,
                    derivedDataPath: derivedDataPath,
                    retryCount: retryCount,
                    testTargets: testTargets,
                    skipTestTargets: skipTestTargets,
                    testPlanConfiguration: testPlanConfiguration,
                    passthroughXcodeBuildArguments: passthroughXcodeBuildArguments
                )
            }
        } else {
            let testSchemes: [Scheme] = buildGraphInspector.workspaceSchemes(graphTraverser: graphTraverser)
                .filter {
                    $0.testAction.map { !$0.targets.isEmpty } ?? false
                }

            if testSchemes.isEmpty {
                logger.log(level: .info, "There are no tests to run, finishing early")
                return
            }

            for testScheme in testSchemes {
                try await self.testScheme(
                    scheme: testScheme,
                    graphTraverser: graphTraverser,
                    clean: clean,
                    configuration: configuration,
                    version: version,
                    deviceName: deviceName,
                    platform: platform,
                    rosetta: rosetta,
                    resultBundlePath: resultBundlePath,
                    derivedDataPath: derivedDataPath,
                    retryCount: retryCount,
                    testTargets: testTargets,
                    skipTestTargets: skipTestTargets,
                    testPlanConfiguration: testPlanConfiguration,
                    passthroughXcodeBuildArguments: passthroughXcodeBuildArguments
                )
            }
        }

        logger.log(level: .notice, "The project tests ran successfully", metadata: .success)

        // Saving hashes from `testsCacheTemporaryDirectory` to `testsCacheDirectory` after all the tests have run successfully
        let cacheableItems: [CacheStorableItem: [AbsolutePath]] = try FileHandler.shared
            .contentsOfDirectory(testsCacheTemporaryDirectory.path)
            .reduce(into: [:]) { acc, hash in
                guard let name = try FileHandler.shared.contentsOfDirectory(hash).first else { return }
                acc[CacheStorableItem(name: name.basename, hash: hash.basename)] = [AbsolutePath]()
            }

        try await cacheStorage.store(cacheableItems, cacheCategory: .selectiveTests)
    }

    // MARK: - Helpers

    /// - Returns: Result bundle path to use. Either passed by the user or a path in the Tuist cache
    private func resultBundlePath(
        passedResultBundlePath: AbsolutePath?,
        runId: String,
        config: Config
    ) throws -> AbsolutePath? {
        let runResultBundlePath = try cacheDirectoryProviderFactory.cacheDirectories()
            .tuistCacheDirectory(for: .runs)
            .appending(components: runId, Constants.resultBundleName)

        if config.cloud == nil {
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
        rosetta: Bool,
        resultBundlePath: AbsolutePath?,
        derivedDataPath: AbsolutePath?,
        retryCount: Int,
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier],
        testPlanConfiguration: TestPlanConfiguration?,
        passthroughXcodeBuildArguments: [String]
    ) async throws {
        logger.log(level: .notice, "Testing scheme \(scheme.name)", metadata: .section)
        if let testPlan = testPlanConfiguration?.testPlan, let testPlans = scheme.testAction?.testPlans,
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
            graphTraverser: graphTraverser
        ) else {
            throw TestServiceError.schemeWithoutTestableTargets(scheme: scheme.name, testPlan: testPlanConfiguration?.testPlan)
        }

        let buildPlatform: XcodeGraph.Platform

        if let platform {
            buildPlatform = try XcodeGraph.Platform.from(commandLineValue: platform)
        } else {
            buildPlatform = try buildableTarget.target.servicePlatform
        }

        let destination = try await XcodeBuildDestination.find(
            for: buildableTarget.target,
            on: buildPlatform,
            scheme: scheme,
            version: version,
            deviceName: deviceName,
            graphTraverser: graphTraverser,
            simulatorController: simulatorController
        )

        try await xcodebuildController.test(
            .workspace(graphTraverser.workspace.xcWorkspacePath),
            scheme: scheme.name,
            clean: clean,
            destination: destination,
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
    }
}
