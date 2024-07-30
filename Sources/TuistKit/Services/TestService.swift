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

    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring
    private let configLoader: ConfigLoading
    private let fileHandler: FileHandling

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
            configLoader: configLoader
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
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.generatorFactory = generatorFactory
        self.cacheStorageFactory = cacheStorageFactory
        self.xcodebuildController = xcodebuildController
        self.buildGraphInspector = buildGraphInspector
        self.simulatorController = simulatorController
        self.contentHasher = contentHasher
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
        self.configLoader = configLoader
        self.fileHandler = fileHandler
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
        let config = try await configLoader.loadConfig(path: path)
        let cacheStorage = try cacheStorageFactory.cacheStorage(config: config)

        let testGenerator = generatorFactory.testing(
            config: config,
            testPlan: testPlanConfiguration?.testPlan,
            includedTargets: Set(testTargets.map(\.target)),
            excludedTargets: Set(skipTestTargets.filter { $0.class == nil }.map(\.target)),
            skipUITests: skipUITests,
            configuration: configuration,
            ignoreBinaryCache: ignoreBinaryCache,
            ignoreSelectiveTesting: ignoreSelectiveTesting,
            cacheStorage: cacheStorage
        )

        logger.notice("Generating project for testing", metadata: .section)
        let (_, graph, mapperEnvironment) = try await testGenerator.generateWithGraph(
            path: path
        )

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
            if let resultBundlePath, let passedResultBundlePath, config.fullHandle != nil {
                if !FileHandler.shared.exists(resultBundlePath.parentDirectory) {
                    try? FileHandler.shared.createFolder(resultBundlePath.parentDirectory)
                }
                try? FileHandler.shared.copy(from: passedResultBundlePath, to: resultBundlePath)
            }
        }

        let testSchemes: [Scheme]
        if let schemeName {
            guard let scheme = graphTraverser.schemes().first(where: { $0.name == schemeName })
            else {
                let schemes = mapperEnvironment.initialGraph.map(GraphTraverser.init)?.schemes() ?? graphTraverser.schemes()
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

            testSchemes = [scheme]

            checkSkippedTargets(
                for: testSchemes,
                mapperEnvironment: mapperEnvironment,
                graph: graph
            )

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
            let allSchemes = buildGraphInspector.workspaceSchemes(graphTraverser: graphTraverser)
            testSchemes = allSchemes
                .filter {
                    $0.testAction.map { !$0.targets.isEmpty } ?? false
                }

            if testSchemes.isEmpty {
                logger.log(level: .info, "There are no tests to run, finishing early")
                return
            }

            checkSkippedTargets(
                for: allSchemes,
                mapperEnvironment: mapperEnvironment,
                graph: graph
            )

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

        try await storeSuccessfulTestHashes(
            for: testSchemes,
            graph: graph,
            mapperEnvironment: mapperEnvironment,
            cacheStorage: cacheStorage
        )

        logger.log(level: .notice, "The project tests ran successfully", metadata: .success)
    }

    // MARK: - Helpers

    private func checkSkippedTargets(
        for schemes: [Scheme],
        mapperEnvironment: MapperEnvironment,
        graph: Graph
    ) {
        let testActionTargets = testActionTargets(for: schemes, graph: graph)
            .map(\.target)
        guard let initialGraph = mapperEnvironment.initialGraph else { return }
        let initialSchemes = GraphTraverser(graph: initialGraph).schemes()
        let initialTestTargets = self.testActionTargets(
            for: initialSchemes
                .filter { initialScheme in
                    schemes.contains(where: { $0.name == initialScheme.name })
                },
            graph: initialGraph
        )
        let skippedTestTargets = initialTestTargets
            .map(\.target)
            .filter { target in
                !testActionTargets.contains(where: {
                    $0.bundleId == target.bundleId
                })
            }
            .map(\.name)
        if !skippedTestTargets.isEmpty {
            logger
                .notice(
                    "The following targets have not changed since the last successful run and will be skipped: \(skippedTestTargets.joined(separator: ", "))"
                )
        }
    }

    private func testActionTargets(
        for schemes: [Scheme],
        graph: Graph
    ) -> [GraphTarget] {
        return schemes.flatMap { $0.testAction?.targets.map(\.target) ?? [] }
            .compactMap {
                guard let project = graph.projects[$0.projectPath],
                      let target = project.targets[$0.name]
                else {
                    return nil
                }
                return GraphTarget(path: project.path, target: target, project: project)
            }
    }

    private func storeSuccessfulTestHashes(
        for schemes: [Scheme],
        graph: Graph,
        mapperEnvironment: MapperEnvironment,
        cacheStorage: CacheStoring
    ) async throws {
        let targets: [GraphTarget] = testActionTargets(
            for: schemes,
            graph: graph
        )
        guard let initialGraph = mapperEnvironment.initialGraph else { return }
        let graphTraverser = GraphTraverser(graph: initialGraph)

        let testedGraphTargets: [GraphTarget] = targets.compactMap {
            guard let project = initialGraph.projects[$0.path],
                  let target = project.targets[$0.target.name] else { return nil }
            return GraphTarget(path: $0.path, target: target, project: project)
        }
        try await fileHandler.inTemporaryDirectory { _ in
            let allTestedTargets: Set<Target> = Set(
                graphTraverser.allTargetDependencies(traversingFromTargets: testedGraphTargets)
                    .union(testedGraphTargets).map(\.target)
            )
            let hashes = mapperEnvironment.testsCacheUntestedHashes.filter { element in
                allTestedTargets.contains(where: { $0.bundleId == element.key.bundleId })
            }

            let cacheableItems: [CacheStorableItem: [AbsolutePath]] = hashes
                .reduce(into: [:]) { acc, element in
                    acc[CacheStorableItem(name: element.key.name, hash: element.value)] = [AbsolutePath]()
                }

            try await cacheStorage.store(cacheableItems, cacheCategory: .selectiveTests)
        }
    }

    /// - Returns: Result bundle path to use. Either passed by the user or a path in the Tuist cache
    private func resultBundlePath(
        passedResultBundlePath: AbsolutePath?,
        runId: String,
        config: Config
    ) throws -> AbsolutePath? {
        let runResultBundlePath = try cacheDirectoryProviderFactory.cacheDirectories()
            .cacheDirectory(for: .runs)
            .appending(components: runId, Constants.resultBundleName)

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
