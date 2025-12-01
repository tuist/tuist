import Path
import TuistCore
import TuistLoader
import TuistSupport
import XcodeGraph

final class InspectRedundantImportsService {
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

    func run(path: String?) async throws {
        let path = try self.path(path)
        let config = try await configLoader.loadConfig(path: path)
        let generator = generatorFactory.defaultGenerator(config: config, includedTargets: [])
        let graph = try await generator.load(
            path: path,
            options: config.project.generatedProject?.generationOptions
        )
        let issues = try await graphImportsLinter.lint(
            graphTraverser: GraphTraverser(graph: graph),
            inspectType: .redundant,
            ignoreTagsMatching: config.inspectOptions.redundantDependencies.ignoreTagsMatching
        )
        if !issues.isEmpty {
            throw InspectImportsServiceError.redundantImportsFound(issues)
        }
        Logger.current.log(
            level: .info,
            "We did not find any redundant dependencies in your project."
        )
    }

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
