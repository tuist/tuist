import Foundation
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport

enum BuildServiceError: FatalError {
    case workspaceNotFound(path: String)
    case schemeWithoutBuildableTargets(scheme: String)
    case schemeNotFound(scheme: String, existing: [String])

    var description: String {
        switch self {
        case let .schemeWithoutBuildableTargets(scheme):
            return "The scheme \(scheme) cannot be built because it contains no buildable targets."
        case let .workspaceNotFound(path):
            return "Workspace not found expected xcworkspace at \(path)"
        case let .schemeNotFound(scheme, existing):
            return "Couldn't find scheme \(scheme). The available schemes are: \(existing.joined(separator: ", "))."
        }
    }

    var type: ErrorType {
        switch self {
        case .workspaceNotFound:
            return .bug
        case .schemeNotFound,
             .schemeWithoutBuildableTargets:
            return .abort
        }
    }
}

final class BuildService {
    private let generatorFactory: GeneratorFactorying
    private let buildGraphInspector: BuildGraphInspecting
    private let targetBuilder: TargetBuilding

    init(
        generatorFactory: GeneratorFactorying = GeneratorFactory(),
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        targetBuilder: TargetBuilding = TargetBuilder()
    ) {
        self.generatorFactory = generatorFactory
        self.buildGraphInspector = buildGraphInspector
        self.targetBuilder = targetBuilder
    }

    func run(
        schemeName: String?,
        generate: Bool,
        clean: Bool,
        configuration: String?,
        buildOutputPath: AbsolutePath?,
        path: AbsolutePath
    ) async throws {
        let graph: Graph
        let generator = generatorFactory.default()
        if try (generate || buildGraphInspector.workspacePath(directory: path) == nil) {
            graph = try await generator.generateWithGraph(path: path).1
        } else {
            graph = try await generator.load(path: path)
        }

        guard let workspacePath = try buildGraphInspector.workspacePath(directory: path) else {
            throw BuildServiceError.workspaceNotFound(path: path.pathString)
        }

        let graphTraverser = GraphTraverser(graph: graph)
        let buildableSchemes = buildGraphInspector.buildableSchemes(graphTraverser: graphTraverser)

        logger.log(
            level: .debug,
            "Found the following buildable schemes: \(buildableSchemes.map(\.name).joined(separator: ", "))"
        )

        if let schemeName = schemeName {
            guard let scheme = buildableSchemes.first(where: { $0.name == schemeName }) else {
                throw BuildServiceError.schemeNotFound(scheme: schemeName, existing: buildableSchemes.map(\.name))
            }

            guard let graphTarget = buildGraphInspector.buildableTarget(scheme: scheme, graphTraverser: graphTraverser) else {
                throw TargetBuilderError.schemeWithoutBuildableTargets(scheme: scheme.name)
            }

            try await targetBuilder.buildTarget(
                graphTarget,
                workspacePath: workspacePath,
                schemeName: scheme.name,
                clean: clean,
                configuration: configuration,
                buildOutputPath: buildOutputPath
            )
        } else {
            var cleaned = false
            // Build only buildable entry schemes when specific schemes has not been passed
            let buildableEntrySchemes = buildGraphInspector.buildableEntrySchemes(graphTraverser: graphTraverser)
            for scheme in buildableEntrySchemes {
                guard let graphTarget = buildGraphInspector.buildableTarget(scheme: scheme, graphTraverser: graphTraverser) else {
                    throw TargetBuilderError.schemeWithoutBuildableTargets(scheme: scheme.name)
                }

                try await targetBuilder.buildTarget(
                    graphTarget,
                    workspacePath: workspacePath,
                    schemeName: scheme.name,
                    clean: !cleaned && clean,
                    configuration: configuration,
                    buildOutputPath: buildOutputPath
                )
                cleaned = true
            }
        }

        logger.log(level: .notice, "The project built successfully", metadata: .success)
    }
}
