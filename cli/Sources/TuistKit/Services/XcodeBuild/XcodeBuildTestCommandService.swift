import FileSystem
import Foundation
import Path
import TuistAutomation
import TuistCache
import TuistCore
import TuistHasher
import TuistLoader
import TuistServer
import TuistSupport
import XcodeGraph
import XcodeGraphMapper

enum XcodeBuildTestCommandServiceError: LocalizedError, Equatable {
    case schemeNotFound(String)
    case schemeNotPassed
    case testPlanNotFound(testPlan: String, scheme: String)

    var errorDescription: String? {
        switch self {
        case let .schemeNotFound(scheme):
            return
                "The scheme \(scheme) was not found in the Xcode project. Make sure it's present."
        case .schemeNotPassed:
            return
                "The xcodebuild invocation contains no scheme. Specify one by adding '-scheme MyScheme'."
        case let .testPlanNotFound(testPlan: testPlan, scheme: scheme):
            return
                "Test plan \(testPlan) for scheme \(scheme) was not found. Make sure it's present."
        }
    }
}

struct XcodeBuildTestCommandService {
    private let fileSystem: FileSysteming
    private let xcodeGraphMapper: XcodeGraphMapping
    private let xcodeBuildController: XcodeBuildControlling
    private let configLoader: ConfigLoading
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let uniqueIDGenerator: UniqueIDGenerating
    private let cacheStorageFactory: CacheStorageFactorying
    private let selectiveTestingGraphHasher: SelectiveTestingGraphHashing
    private let selectiveTestingService: SelectiveTestingServicing
    private let inspectResultBundleService: InspectResultBundleServicing
    private let derivedDataLocator: DerivedDataLocating

    init(
        fileSystem: FileSysteming = FileSystem(),
        xcodeGraphMapper: XcodeGraphMapping = XcodeGraphMapper(),
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        configLoader: ConfigLoading = ConfigLoader(),
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider(),
        uniqueIDGenerator: UniqueIDGenerating = UniqueIDGenerator(),
        cacheStorageFactory: CacheStorageFactorying,
        selectiveTestingGraphHasher: SelectiveTestingGraphHashing,
        selectiveTestingService: SelectiveTestingServicing,
        inspectResultBundleService: InspectResultBundleServicing = InspectResultBundleService(),
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator()
    ) {
        self.fileSystem = fileSystem
        self.xcodeGraphMapper = xcodeGraphMapper
        self.xcodeBuildController = xcodeBuildController
        self.configLoader = configLoader
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.uniqueIDGenerator = uniqueIDGenerator
        self.cacheStorageFactory = cacheStorageFactory
        self.selectiveTestingGraphHasher = selectiveTestingGraphHasher
        self.selectiveTestingService = selectiveTestingService
        self.inspectResultBundleService = inspectResultBundleService
        self.derivedDataLocator = derivedDataLocator
    }

    func run(
        passthroughXcodebuildArguments: [String]
    ) async throws {
        let path = try await path(passthroughXcodebuildArguments: passthroughXcodebuildArguments)
        let config = try await configLoader.loadConfig(path: path)
        try await runTests(
            passthroughXcodebuildArguments: passthroughXcodebuildArguments,
            path: path,
            config: config
        )
    }

    // swiftlint:disable:next function_body_length
    private func runTests(
        passthroughXcodebuildArguments: [String],
        path: AbsolutePath,
        config: Tuist
    ) async throws {
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let projectDerivedDataDirectory: AbsolutePath
        if let derivedDataPathString = Self.passedValue(
            for: "-derivedDataPath", arguments: passthroughXcodebuildArguments
        ) {
            projectDerivedDataDirectory = try AbsolutePath(
                validating: derivedDataPathString,
                relativeTo: currentWorkingDirectory
            )
        } else {
            projectDerivedDataDirectory = try await derivedDataLocator.locate(for: path)
        }

        let cacheStorage = try await cacheStorageFactory.cacheStorage(config: config)
        guard let schemeName = Self.passedValue(
            for: "-scheme", arguments: passthroughXcodebuildArguments
        )
        else {
            throw XcodeBuildTestCommandServiceError.schemeNotPassed
        }
        let graph = try await xcodeGraphMapper.map(at: path)
        await RunMetadataStorage.current.update(graph: graph)
        let graphTraverser = GraphTraverser(graph: graph)
        guard let scheme = graphTraverser.schemes().first(where: {
            $0.name == schemeName
        })
        else {
            throw XcodeBuildTestCommandServiceError.schemeNotFound(schemeName)
        }

        let selectiveTestingHashes = try await selectiveTestingGraphHasher.hash(
            graph: graph,
            additionalStrings: Self.additionalHashableStringsFromXcodebuildPassthroughArguments(
                passthroughXcodebuildArguments
            )
        )
        let selectiveTestingHashStrings = selectiveTestingHashes.mapValues(\.hash)
        let selectiveTestingCacheItems = try await cacheStorage.fetch(
            Set(
                selectiveTestingHashStrings.map {
                    CacheStorableItem(name: $0.key.target.name, hash: $0.value)
                }
            ),
            cacheCategory: .selectiveTests
        )
        .keys
        .map { $0 }

        let testableTargets: [TestableTarget]
        if let testPlanName = Self.passedValue(
            for: "-testPlan", arguments: passthroughXcodebuildArguments
        ) {
            guard let testPlan = scheme.testAction?.testPlans?.first(where: {
                $0.name == testPlanName
            })
            else {
                throw XcodeBuildTestCommandServiceError.testPlanNotFound(
                    testPlan: testPlanName, scheme: scheme.name
                )
            }
            testableTargets = testPlan.testTargets
        } else if let defaultTestPlan = scheme.testAction?.testPlans?.first(where: { $0.isDefault }) {
            testableTargets = defaultTestPlan.testTargets
        } else {
            testableTargets = scheme.testAction?.targets ?? []
        }
        let testableGraphTargets = testableGraphTargets(
            for: testableTargets, graphTraverser: graphTraverser
        )
        let skipTestTargets = try await selectiveTestingService.cachedTests(
            testableGraphTargets: testableGraphTargets,
            selectiveTestingHashes: selectiveTestingHashStrings,
            selectiveTestingCacheItems: selectiveTestingCacheItems
        )

        let targetTestCacheItems: [AbsolutePath: [String: CacheItem]] =
            selectiveTestingHashStrings
                .reduce(into: [:]) { result, element in
                    if let cacheItem = selectiveTestingCacheItems.first(where: {
                        $0.hash == element.value
                    }) {
                        result[element.key.path, default: [:]][element.key.target.name] = cacheItem
                    }
                }

        if testableTargets
            .filter({ testableTarget in
                !skipTestTargets.contains(where: { $0.target == testableTarget.target.name })
            })
            .isEmpty
        {
            Logger.current.info("There are no tests to run, exiting early...")
            await updateRunMetadataStorage(
                with: testableGraphTargets,
                selectiveTestingHashes: selectiveTestingHashStrings,
                targetTestCacheItems: targetTestCacheItems
            )
            return
        }

        if !skipTestTargets.isEmpty {
            Logger.current
                .info(
                    "The following targets have not changed since the last successful run and will be skipped: \(Set(skipTestTargets.compactMap(\.target)).sorted().joined(separator: ", "))"
                )
        }

        let skipTestingArguments = skipTestTargets.map {
            "-skip-testing:\($0.target)"
        }

        let resultBundleArguments = try await resultBundlePathArguments(
            passthroughXcodebuildArguments: passthroughXcodebuildArguments
        )
        let resultBundlePath = await RunMetadataStorage.current.resultBundlePath

        do {
            try await xcodeBuildController
                .run(
                    arguments: [
                        passthroughXcodebuildArguments,
                        skipTestingArguments,
                        resultBundleArguments,
                    ]
                    .flatMap { $0 }
                )
        } catch {
            await updateRunMetadataStorage(
                with: testableGraphTargets,
                selectiveTestingHashes: selectiveTestingHashStrings,
                targetTestCacheItems: targetTestCacheItems
            )
            await inspectResultBundleIfNeeded(
                resultBundlePath: resultBundlePath,
                projectDerivedDataDirectory: projectDerivedDataDirectory,
                config: config
            )
            throw error
        }

        await updateRunMetadataStorage(
            with: testableGraphTargets,
            selectiveTestingHashes: selectiveTestingHashStrings,
            targetTestCacheItems: targetTestCacheItems
        )

        try await storeTestableGraphTargets(
            testableGraphTargets,
            selectiveTestingHashes: selectiveTestingHashStrings,
            targetTestCacheItems: targetTestCacheItems,
            cacheStorage: cacheStorage
        )

        await inspectResultBundleIfNeeded(
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: projectDerivedDataDirectory,
            config: config
        )
    }

    static func additionalHashableStringsFromXcodebuildPassthroughArguments(_ arguments: [String])
        -> [String]
    {
        return [
            "-configuration",
            "-xcconfig",
            "-sdk",
            "-skip-test-configuration",
            "-only-test-configuration",
            "-toolchain",
            "-testPlan",
            // We can be smarter about these and match those with targets to be tested.
            // For now, this is a safe way to ensure we accidentally don't store selective test results for tests that were _not_
            // tested.
            "-skip-testing",
            "-only-testing",
        ]
        .compactMap { passedValue(for: $0, arguments: arguments) }
    }

    private func resultBundlePathArguments(
        passthroughXcodebuildArguments: [String]
    ) async throws -> [String] {
        if let resultBundlePathString = Self.passedValue(
            for: "-resultBundlePath",
            arguments: passthroughXcodebuildArguments
        ) {
            let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
            let resultBundlePath = try AbsolutePath(
                validating: resultBundlePathString, relativeTo: currentWorkingDirectory
            )
            await RunMetadataStorage.current.update(
                resultBundlePath: resultBundlePath
            )
            return []
        } else {
            let resultBundlePath =
                try cacheDirectoriesProvider
                    .cacheDirectory(for: .runs)
                    .appending(components: uniqueIDGenerator.uniqueID())
            await RunMetadataStorage.current.update(
                resultBundlePath: resultBundlePath
            )
            return ["-resultBundlePath", resultBundlePath.pathString]
        }
    }

    private func updateRunMetadataStorage(
        with testableGraphTargets: [GraphTarget],
        selectiveTestingHashes: [GraphTarget: String],
        targetTestCacheItems: [AbsolutePath: [String: CacheItem]]
    ) async {
        await RunMetadataStorage.current.update(
            selectiveTestingCacheItems: testableGraphTargets.reduce(into: [:]) { result, element in
                guard let hash = selectiveTestingHashes[element] else { return }
                let cacheItem =
                    targetTestCacheItems[element.path]?[element.target.name]
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

    private func storeTestableGraphTargets(
        _ testableGraphTargets: [GraphTarget],
        selectiveTestingHashes: [GraphTarget: String],
        targetTestCacheItems: [AbsolutePath: [String: CacheItem]],
        cacheStorage: CacheStoring
    ) async throws {
        let cacheableItems: [CacheStorableItem: [AbsolutePath]] =
            testableGraphTargets
                .filter {
                    return targetTestCacheItems[$0.path]?[$0.target.name] == nil
                }
                .compactMap { graphTarget -> (target: Target, hash: String)? in
                    guard let hash = selectiveTestingHashes[graphTarget]
                    else { return nil }
                    return (target: graphTarget.target, hash: hash)
                }
                .reduce(into: [:]) { acc, element in
                    acc[CacheStorableItem(name: element.target.name, hash: element.hash)] = [
                        AbsolutePath
                    ]()
                }
        try await cacheStorage.store(cacheableItems, cacheCategory: .selectiveTests)
    }

    private func testableGraphTargets(
        for testableTargets: [TestableTarget],
        graphTraverser: GraphTraversing
    ) -> [GraphTarget] {
        testableTargets
            .compactMap { target in
                guard let graphTarget = graphTraverser.targets(at: target.target.projectPath)
                    .first(where: { $0.target.name == target.target.name })
                else { return nil }
                return graphTarget
            }
    }

    private func path(
        passthroughXcodebuildArguments: [String]
    ) async throws -> AbsolutePath {
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        if let workspaceOrProjectPath = Self.passedValue(
            for: "-workspace", arguments: passthroughXcodebuildArguments
        )
            ?? Self.passedValue(for: "-project", arguments: passthroughXcodebuildArguments)
        {
            return try AbsolutePath(
                validating: workspaceOrProjectPath, relativeTo: currentWorkingDirectory
            )
        } else {
            return currentWorkingDirectory
        }
    }

    private static func passedValue(
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
        projectDerivedDataDirectory: AbsolutePath,
        config: Tuist
    ) async {
        guard let resultBundlePath, config.fullHandle != nil,
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
