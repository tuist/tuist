import Foundation
import RxBlocking
import TSCBasic
import struct TSCUtility.Version
import TuistAutomation
import TuistCore
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
    /// Project generator
    let projectGenerator: ProjectGenerating

    /// Xcode build controller.
    let xcodebuildController: XcodeBuildControlling

    /// Build graph inspector.
    let buildGraphInspector: BuildGraphInspecting

    /// Simulator controller
    let simulatorController: SimulatorControlling

    init(
        projectGenerator: ProjectGenerating = ProjectGenerator(),
        xcodebuildController: XcodeBuildControlling = XcodeBuildController(),
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        simulatorController: SimulatorControlling = SimulatorController()
    ) {
        self.projectGenerator = projectGenerator
        self.xcodebuildController = xcodebuildController
        self.buildGraphInspector = buildGraphInspector
        self.simulatorController = simulatorController
    }

    func run(
        schemeName: String?,
        generate: Bool,
        clean: Bool,
        configuration: String?,
        path: AbsolutePath,
        deviceName: String?,
        osVersion: String?
    ) throws {
        let graph: Graph
        if try (generate || buildGraphInspector.workspacePath(directory: path) == nil) {
            graph = try projectGenerator.generateWithGraph(path: path, projectOnly: false).1
        } else {
            graph = try projectGenerator.load(path: path)
        }

        let version = osVersion?.version()

        let testableSchemes = buildGraphInspector.testableSchemes(graph: graph)
        logger.log(
            level: .debug,
            "Found the following testable schemes: \(testableSchemes.map(\.name).joined(separator: ", "))"
        )

        if let schemeName = schemeName {
            guard let scheme = testableSchemes.first(where: { $0.name == schemeName }) else {
                throw TestServiceError.schemeNotFound(scheme: schemeName, existing: testableSchemes.map(\.name))
            }
            try testScheme(
                scheme: scheme,
                graph: graph,
                path: path,
                clean: clean,
                configuration: configuration,
                version: version,
                deviceName: deviceName
            )
        } else {
            var cleaned: Bool = false
            let testSchemes = buildGraphInspector.testSchemes(graph: graph)
            try testSchemes.forEach {
                try testScheme(
                    scheme: $0,
                    graph: graph,
                    path: path,
                    clean: !cleaned && clean,
                    configuration: configuration,
                    version: version,
                    deviceName: deviceName
                )
                cleaned = true
            }
        }

        logger.log(level: .notice, "The project tests ran successfully", metadata: .success)
    }

    // MARK: - private

    private func testScheme(
        scheme: Scheme,
        graph: Graph,
        path: AbsolutePath,
        clean: Bool,
        configuration: String?,
        version: Version?,
        deviceName: String?
    ) throws {
        logger.log(level: .notice, "Testing scheme \(scheme.name)", metadata: .section)
        guard let buildableTarget = buildGraphInspector.testableTarget(scheme: scheme, graph: graph) else {
            throw TestServiceError.schemeWithoutTestableTargets(scheme: scheme.name)
        }

        let destination: XcodeBuildDestination
        switch buildableTarget.platform {
        case .iOS, .tvOS, .watchOS:
            let minVersion: Version?
            if let deploymentTarget = buildableTarget.deploymentTarget {
                minVersion = deploymentTarget.version.version()
            } else {
                minVersion = scheme.targetDependencies()
                    .compactMap { graph.findTargetNode(path: $0.projectPath, name: $0.name) }
                    .flatMap { $0.targetDependencies.compactMap { $0.target.deploymentTarget?.version } }
                    .compactMap { $0.version() }
                    .sorted()
                    .first
            }
            let device = try simulatorController.findAvailableDevice(
                platform: buildableTarget.platform,
                version: version,
                minVersion: minVersion,
                deviceName: deviceName
            )
            .toBlocking()
            .single()
            destination = .device(device.udid)
        case .macOS:
            destination = .mac
        }

        let workspacePath = try buildGraphInspector.workspacePath(directory: path)!
        _ = try xcodebuildController.test(
            .workspace(workspacePath),
            scheme: scheme.name,
            clean: clean,
            destination: destination,
            arguments: buildGraphInspector.buildArguments(target: buildableTarget, configuration: configuration)
        )
        .printFormattedOutput()
        .toBlocking()
        .last()
    }
}
