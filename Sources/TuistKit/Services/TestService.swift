import Foundation
import RxBlocking
import RxSwift
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

    // Error description
    var description: String {
        switch self {
        case let .schemeNotFound(scheme, existing):
            return "Couldn't find scheme \(scheme). The available schemes are: \(existing.joined(separator: ", "))."
        case let .schemeWithoutTestableTargets(scheme):
            return "The scheme \(scheme) cannot be built because it contains no buildable targets."
        }
    }

    // Error type
    var type: ErrorType {
        switch self {
        case .schemeNotFound:
            return .abort
        case .schemeWithoutTestableTargets:
            return .abort
        }
    }
}

final class TestService {
    private let testServiceGeneratorFactory: TestServiceGeneratorFactorying
    private let xcodebuildController: XcodeBuildControlling
    private let buildGraphInspector: BuildGraphInspecting
    private let simulatorController: SimulatorControlling

    private let temporaryDirectory: TemporaryDirectory
    private let testsCacheTemporaryDirectory: TemporaryDirectory

    convenience init() throws {
        let temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let testsCacheTemporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        self.init(
            temporaryDirectory: temporaryDirectory,
            testsCacheTemporaryDirectory: testsCacheTemporaryDirectory,
            testServiceGeneratorFactory: TestServiceGeneratorFactory()
        )
    }

    init(
        temporaryDirectory: TemporaryDirectory,
        testsCacheTemporaryDirectory: TemporaryDirectory,
        testServiceGeneratorFactory: TestServiceGeneratorFactorying,
        xcodebuildController: XcodeBuildControlling = XcodeBuildController(),
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        simulatorController: SimulatorControlling = SimulatorController()
    ) {
        self.temporaryDirectory = temporaryDirectory
        self.testsCacheTemporaryDirectory = testsCacheTemporaryDirectory
        self.testServiceGeneratorFactory = testServiceGeneratorFactory
        self.xcodebuildController = xcodebuildController
        self.buildGraphInspector = buildGraphInspector
        self.simulatorController = simulatorController
    }

    func run(
        schemeName: String?,
        clean: Bool,
        configuration: String?,
        path: AbsolutePath,
        deviceName: String?,
        osVersion: String?
    ) throws {
        let generator = testServiceGeneratorFactory.generator(
            automationPath: Environment.shared.automationPath ?? temporaryDirectory.path,
            testsCacheDirectory: testsCacheTemporaryDirectory.path
        )
        logger.notice("Generating project for testing", metadata: .section)
        let graph = ValueGraph(
            graph: try generator.generateWithGraph(
                path: path,
                projectOnly: false
            ).1
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let version = osVersion?.version()

        let testableSchemes = buildGraphInspector.testableSchemes(graphTraverser: graphTraverser) + buildGraphInspector.projectSchemes(graphTraverser: graphTraverser)
        logger.log(
            level: .debug,
            "Found the following testable schemes: \(Set(testableSchemes.map(\.name)).joined(separator: ", "))"
        )

        if let schemeName = schemeName {
            guard
                let scheme = testableSchemes.first(where: { $0.name == schemeName })
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

            try testSchemes.forEach { testScheme in
                try self.testScheme(
                    scheme: testScheme,
                    graphTraverser: graphTraverser,
                    clean: clean,
                    configuration: configuration,
                    version: version,
                    deviceName: deviceName
                )
            }
        } else {
            let testSchemes: [Scheme] = buildGraphInspector.projectSchemes(graphTraverser: graphTraverser)
                .filter {
                    $0.testAction.map { !$0.targets.isEmpty } ?? false
                }

            if testSchemes.isEmpty {
                logger.log(level: .info, "There are no tests to run, finishing early")
                return
            }

            try testSchemes.forEach {
                try testScheme(
                    scheme: $0,
                    graphTraverser: graphTraverser,
                    clean: clean,
                    configuration: configuration,
                    version: version,
                    deviceName: deviceName
                )
            }

            if !FileHandler.shared.exists(
                Environment.shared.testsCacheDirectory
            ) {
                try FileHandler.shared.createFolder(Environment.shared.testsCacheDirectory)
            }

            // Saving hashes to `testsCacheTemporaryDirectory` after all the tests have run successfully
            try FileHandler.shared
                .contentsOfDirectory(testsCacheTemporaryDirectory.path)
                .forEach { hashPath in
                    let destination = Environment.shared.testsCacheDirectory.appending(component: hashPath.basename)
                    guard !FileHandler.shared.exists(destination) else { return }
                    try FileHandler.shared.move(
                        from: hashPath,
                        to: destination
                    )
                }
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
        deviceName: String?
    ) throws {
        logger.log(level: .notice, "Testing scheme \(scheme.name)", metadata: .section)
        guard let buildableTarget = buildGraphInspector.testableTarget(scheme: scheme, graphTraverser: graphTraverser) else {
            throw TestServiceError.schemeWithoutTestableTargets(scheme: scheme.name)
        }

        let destination = try findDestination(
            target: buildableTarget.target,
            scheme: scheme,
            graphTraverser: graphTraverser,
            version: version,
            deviceName: deviceName
        )

        _ = try xcodebuildController.test(
            .workspace(graphTraverser.workspace.xcWorkspacePath),
            scheme: scheme.name,
            clean: clean,
            destination: destination,
            derivedDataPath: nil,
            arguments: buildGraphInspector.buildArguments(
                project: buildableTarget.project,
                target: buildableTarget.target,
                configuration: configuration,
                skipSigning: true
            )
        )
        .printFormattedOutput()
        .toBlocking()
        .last()
    }

    private func findDestination(
        target: Target,
        scheme: Scheme,
        graphTraverser: GraphTraversing,
        version: Version?,
        deviceName: String?
    ) throws -> XcodeBuildDestination {
        switch target.platform {
        case .iOS, .tvOS, .watchOS:
            let minVersion: Version?
            if let deploymentTarget = target.deploymentTarget {
                minVersion = deploymentTarget.version.version()
            } else {
                minVersion = scheme.targetDependencies()
                    .flatMap {
                        graphTraverser
                            .directTargetDependencies(path: $0.projectPath, name: $0.name)
                            .map(\.target)
                            .map(\.deploymentTarget)
                            .compactMap { $0?.version.version() }
                    }
                    .sorted()
                    .first
            }
            let deviceAndRuntime = try simulatorController.findAvailableDevice(
                platform: target.platform,
                version: version,
                minVersion: minVersion,
                deviceName: deviceName
            )
            .toBlocking()
            .single()
            return .device(deviceAndRuntime.device.udid)
        case .macOS:
            return .mac
        }
    }
}
