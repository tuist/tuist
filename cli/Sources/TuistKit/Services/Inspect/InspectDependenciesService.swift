import Foundation
import Path
import TuistCore
import TuistLoader
import TuistSupport
import XcodeGraph

final class InspectDependenciesService {
    private let configLoader: ConfigLoading
    private let generatorFactory: GeneratorFactorying
    private let graphImportsLinter: GraphImportsLinting

    init(
        generatorFactory: GeneratorFactorying = GeneratorFactory(),
        configLoader: ConfigLoading = ConfigLoader(),
        graphImportsLinter: GraphImportsLinting = GraphImportsLinter()
    ) {
        self.configLoader = configLoader
        self.generatorFactory = generatorFactory
        self.graphImportsLinter = graphImportsLinter
    }

    func run(
        path: String?,
        inspectionTypes: Set<DependencyInspectionType>
    ) async throws {
        let path = try self.path(path)
        let config = try await configLoader.loadConfig(path: path)
        let generator = generatorFactory.defaultGenerator(config: config, includedTargets: [])
        let graph = try await generator.load(
            path: path,
            options: config.project.generatedProject?.generationOptions
        )
        let graphTraverser = GraphTraverser(graph: graph)

        var checksRun: [String] = []

        if inspectionTypes.contains(.implicit) {
            try await runImplicitCheck(graphTraverser: graphTraverser)
            checksRun.append("implicit")
        }

        if inspectionTypes.contains(.redundant) {
            try await runRedundantCheck(
                graphTraverser: graphTraverser,
                ignoreTagsMatching: config.inspectOptions.redundantDependencies.ignoreTagsMatching
            )
            checksRun.append("redundant")
        }

        Logger.current.log(
            level: .info,
            "We did not find any dependency issues in your project (checked: \(checksRun.joined(separator: ", ")))."
        )
    }

    private func runImplicitCheck(graphTraverser: GraphTraverser) async throws {
        let issues = try await graphImportsLinter.lint(
            graphTraverser: graphTraverser,
            inspectType: .implicit,
            ignoreTagsMatching: []
        )
        if !issues.isEmpty {
            throw InspectImportsServiceError.implicitImportsFound(issues)
        }
    }

    private func runRedundantCheck(
        graphTraverser: GraphTraverser,
        ignoreTagsMatching: Set<String>
    ) async throws {
        let issues = try await graphImportsLinter.lint(
            graphTraverser: graphTraverser,
            inspectType: .redundant,
            ignoreTagsMatching: ignoreTagsMatching
        )
        if !issues.isEmpty {
            throw InspectImportsServiceError.redundantImportsFound(issues)
        }
    }

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
