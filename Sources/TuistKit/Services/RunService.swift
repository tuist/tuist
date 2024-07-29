import Foundation
import Path
import struct TSCUtility.Version
import TuistAutomation
import TuistCore
import TuistLoader
import TuistSupport
import XcodeGraph

enum RunServiceError: FatalError {
    case schemeNotFound(scheme: String, existing: [String])
    case schemeWithoutRunnableTarget(scheme: String)
    case invalidVersion(String)
    case workspaceNotFound(path: String)

    var description: String {
        switch self {
        case let .schemeNotFound(scheme, existing):
            return "Couldn't find scheme \(scheme). The available schemes are: \(existing.joined(separator: ", "))."
        case let .schemeWithoutRunnableTarget(scheme):
            return "The scheme \(scheme) cannot be run because it contains no runnable target."
        case let .invalidVersion(version):
            return "The version \(version) is not a valid version specifier."
        case let .workspaceNotFound(path):
            return "Workspace not found expected xcworkspace at \(path)"
        }
    }

    var type: ErrorType {
        switch self {
        case .schemeNotFound,
             .schemeWithoutRunnableTarget,
             .invalidVersion:
            return .abort
        case .workspaceNotFound:
            return .bug
        }
    }
}

final class RunService {
    private let generatorFactory: GeneratorFactorying
    private let buildGraphInspector: BuildGraphInspecting
    private let targetBuilder: TargetBuilding
    private let targetRunner: TargetRunning
    private let configLoader: ConfigLoading

    init(
        generatorFactory: GeneratorFactorying = GeneratorFactory(),
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        targetBuilder: TargetBuilding = TargetBuilder(),
        targetRunner: TargetRunning = TargetRunner(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader())
    ) {
        self.generatorFactory = generatorFactory
        self.buildGraphInspector = buildGraphInspector
        self.targetBuilder = targetBuilder
        self.targetRunner = targetRunner
        self.configLoader = configLoader
    }

    // swiftlint:disable:next function_body_length
    func run(
        path: String?,
        schemeName: String,
        generate: Bool,
        clean: Bool,
        configuration: String?,
        device: String?,
        version: String?,
        rosetta: Bool,
        arguments: [String]
    ) async throws {
        let runPath: AbsolutePath
        if let path {
            runPath = try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            runPath = FileHandler.shared.currentPath
        }

        let graph: Graph
        let config = try await configLoader.loadConfig(path: runPath)
        let generator = generatorFactory.defaultGenerator(config: config)
        if try (generate || buildGraphInspector.workspacePath(directory: runPath) == nil) {
            logger.notice("Generating project for running", metadata: .section)
            graph = try await generator.generateWithGraph(path: runPath).1
        } else {
            graph = try await generator.load(path: runPath)
        }

        guard let workspacePath = try buildGraphInspector.workspacePath(directory: runPath) else {
            throw RunServiceError.workspaceNotFound(path: runPath.pathString)
        }

        let graphTraverser = GraphTraverser(graph: graph)
        let runnableSchemes = buildGraphInspector.runnableSchemes(graphTraverser: graphTraverser)

        logger.debug("Found the following runnable schemes: \(runnableSchemes.map(\.name).joined(separator: ", "))")

        guard let scheme = runnableSchemes.first(where: { $0.name == schemeName }) else {
            throw RunServiceError.schemeNotFound(scheme: schemeName, existing: runnableSchemes.map(\.name))
        }

        guard let graphTarget = buildGraphInspector.runnableTarget(scheme: scheme, graphTraverser: graphTraverser) else {
            throw RunServiceError.schemeWithoutRunnableTarget(scheme: scheme.name)
        }

        try targetRunner.assertCanRunTarget(graphTarget.target)

        try await targetBuilder.buildTarget(
            graphTarget,
            platform: try graphTarget.target.servicePlatform,
            workspacePath: workspacePath,
            scheme: scheme,
            clean: clean,
            configuration: configuration,
            buildOutputPath: nil,
            derivedDataPath: nil,
            device: device,
            osVersion: version?.version().map { .init(stringLiteral: $0.description) },
            rosetta: rosetta,
            graphTraverser: graphTraverser,
            passthroughXcodeBuildArguments: []
        )

        let minVersion: Version?
        if let deploymentTargetVersion = graphTarget.target.deploymentTargets.configuredVersions.first?.1 {
            minVersion = deploymentTargetVersion.version()
        } else {
            minVersion = scheme.targetDependencies()
                .flatMap {
                    graphTraverser
                        .directLocalTargetDependencies(path: $0.projectPath, name: $0.name)
                        .flatMap(\.target.deploymentTargets.configuredVersions)
                        .compactMap { $0.1.version() }
                }
                .sorted()
                .first
        }

        let version: Version? = try version.map { versionString in
            guard let version = versionString.version() else {
                throw RunServiceError.invalidVersion(versionString)
            }
            return version
        } ?? nil

        try await targetRunner.runTarget(
            graphTarget,
            platform: try graphTarget.target.servicePlatform,
            workspacePath: workspacePath,
            schemeName: scheme.name,
            configuration: configuration,
            minVersion: minVersion,
            version: version,
            deviceName: device,
            arguments: arguments
        )
    }
}
