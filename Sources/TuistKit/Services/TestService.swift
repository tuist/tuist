import Foundation
import TSCBasic
import struct TSCUtility.Version
import TuistAutomation
import TuistCache
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport

enum TestServiceError: FatalError {
    case schemeNotFound(scheme: String, existing: [String])
    case schemeWithoutTestableTargets(scheme: String)
    case cantDeterminePlatform(target: Target)

    // Error description
    var description: String {
        switch self {
        case let .schemeNotFound(scheme, existing):
            return "Couldn't find scheme \(scheme). The available schemes are: \(existing.joined(separator: ", "))."
        case let .schemeWithoutTestableTargets(scheme):
            return "The scheme \(scheme) cannot be built because it contains no buildable targets."
        case let .cantDeterminePlatform(target):
            return "Only single platform targets supported. The target \(target.name) specifies multiple supported platforms (\(target.supportedPlatforms.map(\.rawValue).joined(separator: ", ")))."
        }
    }

    // Error type
    var type: ErrorType {
        switch self {
        case .schemeNotFound, .schemeWithoutTestableTargets, .cantDeterminePlatform:
            return .abort
        }
    }
}

final class TestService {
    private let generatorFactory: GeneratorFactorying
    private let xcodebuildController: XcodeBuildControlling
    private let buildGraphInspector: BuildGraphInspecting
    private let simulatorController: SimulatorControlling
    private let contentHasher: ContentHashing

    private let testsCacheTemporaryDirectory: TemporaryDirectory
    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring

    convenience init() throws {
        let testsCacheTemporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        self.init(
            testsCacheTemporaryDirectory: testsCacheTemporaryDirectory,
            generatorFactory: GeneratorFactory()
        )
    }

    init(
        testsCacheTemporaryDirectory: TemporaryDirectory,
        generatorFactory: GeneratorFactorying,
        xcodebuildController: XcodeBuildControlling = XcodeBuildController(),
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        simulatorController: SimulatorControlling = SimulatorController(),
        contentHasher: ContentHashing = ContentHasher(),
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring = CacheDirectoriesProviderFactory()
    ) {
        self.testsCacheTemporaryDirectory = testsCacheTemporaryDirectory
        self.generatorFactory = generatorFactory
        self.xcodebuildController = xcodebuildController
        self.buildGraphInspector = buildGraphInspector
        self.simulatorController = simulatorController
        self.contentHasher = contentHasher
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
    }

    // swiftlint:disable:next function_body_length
    func run(
        schemeName: String?,
        clean: Bool,
        configuration: String?,
        path: AbsolutePath,
        deviceName: String?,
        osVersion: String?,
        skipUITests: Bool,
        resultBundlePath: AbsolutePath?,
        retryCount: Int
    ) async throws {
        // Load config
        let manifestLoaderFactory = ManifestLoaderFactory()
        let manifestLoader = manifestLoaderFactory.createManifestLoader()
        let configLoader = ConfigLoader(manifestLoader: manifestLoader)
        let config = try configLoader.loadConfig(path: path)
        let cacheDirectoriesProvider = try cacheDirectoryProviderFactory.cacheDirectories(config: config)

        let projectDirectory = cacheDirectoriesProvider.cacheDirectory(for: .generatedAutomationProjects)
            .appending(component: "\(try contentHasher.hash(path.pathString))")
        if !FileHandler.shared.exists(projectDirectory) {
            try FileHandler.shared.createFolder(projectDirectory)
        }

        let generator = generatorFactory.test(
            config: config,
            automationPath: Environment.shared.automationPath ?? projectDirectory,
            testsCacheDirectory: testsCacheTemporaryDirectory.path,
            skipUITests: skipUITests
        )
        logger.notice("Generating project for testing", metadata: .section)
        let graph = try await generator.generateWithGraph(
            path: path
        ).1
        let graphTraverser = GraphTraverser(graph: graph)
        let version = osVersion?.version()

        let testableSchemes = buildGraphInspector.testableSchemes(graphTraverser: graphTraverser) +
            buildGraphInspector.workspaceSchemes(graphTraverser: graphTraverser)
        logger.log(
            level: .debug,
            "Found the following testable schemes: \(Set(testableSchemes.map(\.name)).joined(separator: ", "))"
        )

        if let schemeName = schemeName {
            guard let scheme = testableSchemes.first(where: { $0.name == schemeName })
            else {
                throw TestServiceError.schemeNotFound(
                    scheme: schemeName,
                    existing: testableSchemes.map(\.name)
                )
            }

            if scheme.testAction.map(\.targets.isEmpty) ?? true {
                logger.log(level: .info, "There are no tests to run, finishing early")
                return
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
                    resultBundlePath: resultBundlePath,
                    retryCount: retryCount
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
                    resultBundlePath: resultBundlePath,
                    retryCount: retryCount
                )
            }
        }

        // Saving hashes from `testsCacheTemporaryDirectory` to `testsCacheDirectory` after all the tests have run successfully

        if !FileHandler.shared.exists(
            cacheDirectoriesProvider.cacheDirectory(for: .tests)
        ) {
            try FileHandler.shared.createFolder(cacheDirectoriesProvider.cacheDirectory(for: .tests))
        }

        try FileHandler.shared
            .contentsOfDirectory(testsCacheTemporaryDirectory.path)
            .forEach { hashPath in
                let destination = cacheDirectoriesProvider.cacheDirectory(for: .tests).appending(component: hashPath.basename)
                guard !FileHandler.shared.exists(destination) else { return }
                try FileHandler.shared.move(
                    from: hashPath,
                    to: destination
                )
            }

        logger.log(level: .notice, "The project tests ran successfully", metadata: .success)
    }

    // MARK: - Helpers

    private func testScheme(
        scheme: Scheme,
        graphTraverser: GraphTraversing,
        clean: Bool,
        configuration: String?,
        version: Version?,
        deviceName: String?,
        resultBundlePath: AbsolutePath?,
        retryCount: Int
    ) async throws {
        logger.log(level: .notice, "Testing scheme \(scheme.name)", metadata: .section)
        guard let buildableTarget = buildGraphInspector.testableTarget(scheme: scheme, graphTraverser: graphTraverser) else {
            throw TestServiceError.schemeWithoutTestableTargets(scheme: scheme.name)
        }

        guard let platform = buildableTarget.target.exclusivePlatform else {
            throw TestServiceError.cantDeterminePlatform(target: buildableTarget.target)
        }

        let destination = try await XcodeBuildDestination.find(
            for: buildableTarget.target,
            on: platform,
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
            derivedDataPath: nil,
            resultBundlePath: resultBundlePath,
            arguments: buildGraphInspector.buildArguments(
                project: buildableTarget.project,
                target: buildableTarget.target,
                configuration: configuration,
                skipSigning: false
            ),
            retryCount: retryCount
        )
        .printFormattedOutput()
    }
}
