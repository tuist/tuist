import FileSystem
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

    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming

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
        analyticsDelegate _: TrackableParametersDelegate? = nil,
        xcodebuildController: XcodeBuildControlling = XcodeBuildController(),
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        simulatorController: SimulatorControlling = SimulatorController(),
        contentHasher: ContentHashing = ContentHasher(),
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider(),
        configLoader: ConfigLoading,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.generatorFactory = generatorFactory
        self.cacheStorageFactory = cacheStorageFactory
        self.xcodebuildController = xcodebuildController
        self.buildGraphInspector = buildGraphInspector
        self.simulatorController = simulatorController
        self.contentHasher = contentHasher
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.configLoader = configLoader
        self.fileSystem = fileSystem
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
        passthroughXcodeBuildArguments: [String],
        analyticsDelegate: TrackableParametersDelegate?
    ) async throws {
        if validateTestTargetsParameters {
            try Self.validateParameters(
                testTargets: testTargets,
                skipTestTargets: skipTestTargets
            )
        }
        // Load config
        let config = try await configLoader.loadConfig(path: path)
        let cacheStorage = try await cacheStorageFactory.cacheStorage(config: config)

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

        analyticsDelegate?.targetHashes = mapperEnvironment.targetHashes
        analyticsDelegate?.graphPath = graph.path
        analyticsDelegate?.cacheableTargets = mapperEnvironment.cacheableTargets
        analyticsDelegate?.cacheItems = mapperEnvironment.targetCacheItems.values.flatMap(\.values)

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

        let runResultBundlePath = try cacheDirectoriesProvider
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
                let schemes = mapperEnvironment.initialGraph.map(GraphTraverser.init)?.schemes() ?? graphTraverser.schemes()
                if let scheme = schemes.first(where: { $0.name == schemeName }) {
                    logger.log(level: .info, "The scheme \(schemeName)'s test action has no tests to run, finishing early.")
                    updateTestServiceAnalytics(
                        analyticsDelegate: analyticsDelegate,
                        mapperEnvironment: mapperEnvironment,
                        schemes: [scheme],
                        testPlanConfiguration: testPlanConfiguration
                    )
                    return
                } else {
                    throw TestServiceError.schemeNotFound(
                        scheme: schemeName,
                        existing: Set(schemes.map(\.name)).map { $0 }
                    )
                }
            }

            updateTestServiceAnalytics(
                analyticsDelegate: analyticsDelegate,
                mapperEnvironment: mapperEnvironment,
                schemes: [scheme],
                testPlanConfiguration: testPlanConfiguration
            )

            guard let testAction = scheme.testAction else {
                logger.log(level: .info, "The scheme \(schemeName)'s has not any test actions to run, finishing early.")
                return
            }

            if let testPlanConfiguration {
                guard let testPlans = testAction.testPlans else {
                    logger.log(level: .info, "The scheme \(schemeName)'s test action has no test plans to run, finishing early.")
                    return
                }

                let hasTestPlanConfiguration = testPlans.contains { $0.name == testPlanConfiguration.testPlan }
                if !hasTestPlanConfiguration {
                    logger.log(
                        level: .info,
                        "The scheme \(schemeName)'s test action has no test plan \"\(testPlanConfiguration.testPlan)\" to run, finishing early."
                    )
                    return
                }
            } else if let testPlans = testAction.testPlans, !testPlans.contains(where: \.isDefault) {
                logger.log(
                    level: .info,
                    "The scheme \(schemeName)'s test action has no default test plan to run, finishing early."
                )
                return
            } else if testAction.targets.isEmpty {
                logger.log(level: .info, "The scheme \(schemeName)'s test action has no tests to run, finishing early.")
                return
            }

            schemes = [scheme]
        } else {
            schemes = buildGraphInspector.workspaceSchemes(graphTraverser: graphTraverser)
            updateTestServiceAnalytics(
                analyticsDelegate: analyticsDelegate,
                mapperEnvironment: mapperEnvironment,
                schemes: schemes,
                testPlanConfiguration: testPlanConfiguration
            )
        }

        do {
            try await testSchemes(
                schemes,
                graph: graph,
                mapperEnvironment: mapperEnvironment,
                cacheStorage: cacheStorage,
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
    }

    // MARK: - Helpers

    private func testSchemes(
        _ schemes: [Scheme],
        graph: Graph,
        mapperEnvironment: MapperEnvironment,
        cacheStorage: CacheStoring,
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
        let graphTraverser = GraphTraverser(graph: graph)
        var testSchemes: [Scheme] = []
        var skippedTestTargets: [GraphTarget] = initialTestTargets(
            mapperEnvironment: mapperEnvironment,
            schemes: schemes,
            testPlanConfiguration: testPlanConfiguration
        )

        for scheme in schemes {
            let testActionTargets = testActionTargets(
                for: scheme,
                testPlanConfiguration: testPlanConfiguration,
                graph: graph
            )

            guard !testActionTargets.isEmpty else {
                continue
            }

            testSchemes.append(scheme)

            skippedTestTargets.removeAll { target in
                !testActionTargets.contains(where: {
                    $0.target.bundleId == target.target.bundleId
                })
            }
        }

        guard !testSchemes.isEmpty else {
            logger.log(level: .info, "There are no tests to run, finishing early")
            return
        }

        if !skippedTestTargets.isEmpty {
            logger
                .notice(
                    "The following targets have not changed since the last successful run and will be skipped: \(skippedTestTargets.map(\.target.name).joined(separator: ", "))"
                )
        }

        for testScheme in schemes {
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

        try await storeSuccessfulTestHashes(
            for: testSchemes,
            testPlanConfiguration: testPlanConfiguration,
            graph: graph,
            mapperEnvironment: mapperEnvironment,
            cacheStorage: cacheStorage
        )

        logger.log(level: .notice, "The project tests ran successfully", metadata: .success)
    }

    private func updateTestServiceAnalytics(
        analyticsDelegate: TrackableParametersDelegate?,
        mapperEnvironment: MapperEnvironment,
        schemes: [Scheme],
        testPlanConfiguration: TestPlanConfiguration?
    ) {
        let initialTestTargets = initialTestTargets(
            mapperEnvironment: mapperEnvironment,
            schemes: schemes,
            testPlanConfiguration: testPlanConfiguration
        )
        let testTargets = initialTestTargets
            .map(\.target.name)

        let localTestTargetHits = initialTestTargets
            .filter {
                guard let cacheItem = mapperEnvironment.targetCacheItems[$0.path]?[$0.target.name]
                else { return false }
                return cacheItem.cacheCategory == .selectiveTests && cacheItem.source == .local
            }
            .map(\.target.name)

        let remoteTestTargetHits = initialTestTargets
            .filter {
                guard let cacheItem = mapperEnvironment.targetCacheItems[$0.path]?[$0.target.name]
                else { return false }
                return cacheItem.cacheCategory == .selectiveTests && cacheItem.source == .remote
            }
            .map(\.target.name)

        analyticsDelegate?.selectiveTestsAnalytics = SelectiveTestsAnalytics(
            testTargets: testTargets,
            localTestTargetHits: localTestTargetHits,
            remoteTestTargetHits: remoteTestTargetHits
        )
    }

    private func copyResultBundlePathIfNeeded(
        runResultBundlePath: AbsolutePath?,
        resultBundlePath: AbsolutePath?
    ) async throws {
        if let runResultBundlePath, let resultBundlePath, runResultBundlePath != resultBundlePath {
            if try await !fileSystem.exists(resultBundlePath.parentDirectory) {
                try await fileSystem.makeDirectory(at: resultBundlePath.parentDirectory)
            }
            try await fileSystem.copy(
                try await fileSystem.resolveSymbolicLink(resultBundlePath),
                to: runResultBundlePath.parentDirectory.appending(components: "\(Constants.resultBundleName).xcresult")
            )
        }
    }

    private func initialTestTargets(
        mapperEnvironment: MapperEnvironment,
        schemes: [Scheme],
        testPlanConfiguration: TestPlanConfiguration?
    ) -> [GraphTarget] {
        guard let initialGraph = mapperEnvironment.initialGraph else { return [] }
        let initialSchemes = GraphTraverser(graph: initialGraph).schemes()
        return initialSchemes.lazy
            .filter { initialScheme in
                schemes.contains(where: { $0.name == initialScheme.name })
            }
            .flatMap {
                testActionTargets(
                    for: $0,
                    testPlanConfiguration: testPlanConfiguration,
                    graph: initialGraph
                )
            }
    }

    private func testActionTargets(
        for scheme: Scheme,
        testPlanConfiguration: TestPlanConfiguration?,
        graph: Graph
    ) -> [GraphTarget] {
        guard let testAction = scheme.testAction else {
            return []
        }

        let testTargets: [TestableTarget] = if let testPlanConfiguration {
            testAction.testPlans?
                .first(where: { $0.name == testPlanConfiguration.testPlan })?
                .testTargets ?? []
        } else if let defaultTestPlan = testAction.testPlans?.first(where: \.isDefault) {
            defaultTestPlan.testTargets
        } else if !testAction.targets.isEmpty {
            testAction.targets
        } else {
            []
        }

        return testTargets.compactMap { testTarget in
            let targetReference = testTarget.target
            guard let project = graph.projects[targetReference.projectPath],
                  let target = project.targets[targetReference.name]
            else {
                return nil
            }
            return GraphTarget(path: project.path, target: target, project: project)
        }
    }

    private func storeSuccessfulTestHashes(
        for schemes: [Scheme],
        testPlanConfiguration: TestPlanConfiguration?,
        graph: Graph,
        mapperEnvironment: MapperEnvironment,
        cacheStorage: CacheStoring
    ) async throws {
        let targets: [GraphTarget] = schemes.flatMap {
            testActionTargets(
                for: $0,
                testPlanConfiguration: testPlanConfiguration,
                graph: graph
            )
        }
        guard let initialGraph = mapperEnvironment.initialGraph else { return }
        let graphTraverser = GraphTraverser(graph: initialGraph)

        let testedGraphTargets: [GraphTarget] = targets.compactMap {
            guard let project = initialGraph.projects[$0.path],
                  let target = project.targets[$0.target.name] else { return nil }
            return GraphTarget(path: $0.path, target: target, project: project)
        }
        try await fileSystem.runInTemporaryDirectory(prefix: "test") { _ in
            let allTestedTargets: Set<GraphTarget> = Set(
                graphTraverser.allTargetDependencies(traversingFromTargets: testedGraphTargets)
                    .union(testedGraphTargets)
            )

            let hashes = allTestedTargets
                .filter {
                    if let cacheItem = mapperEnvironment.targetCacheItems[$0.path]?[$0.target.name] {
                        return cacheItem.cacheCategory != .selectiveTests
                    } else {
                        return true
                    }
                }
                .compactMap { graphTarget -> (target: Target, hash: String)? in
                    guard let hash = mapperEnvironment.targetTestHashes[graphTarget.path]?[graphTarget.target.name]
                    else { return nil }
                    return (target: graphTarget.target, hash: hash)
                }

            let cacheableItems: [CacheStorableItem: [AbsolutePath]] = hashes
                .reduce(into: [:]) { acc, element in
                    acc[CacheStorableItem(name: element.target.name, hash: element.hash)] = [AbsolutePath]()
                }

            try await cacheStorage.store(cacheableItems, cacheCategory: .selectiveTests)
        }
    }

    /// - Returns: Result bundle path to use. Either passed by the user or a path in the Tuist cache
    private func resultBundlePath(
        runResultBundlePath: AbsolutePath,
        passedResultBundlePath: AbsolutePath?,
        config: Config
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
