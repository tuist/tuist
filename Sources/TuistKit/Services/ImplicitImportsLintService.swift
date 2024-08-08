import Foundation
import Path
import TuistCore
import TuistLoader

class ImplicitImportsLintService {
    private let graphImplicitLintService: GraphImplicitImportLintService
    private let configLoader: ConfigLoading
    private let generatorFactory: GeneratorFactorying

    init(
        graphImplicitLintService: GraphImplicitImportLintService,
        generatorFactory: GeneratorFactorying,
        configLoader: ConfigLoading
    ) {
        self.graphImplicitLintService = graphImplicitLintService
        self.configLoader = configLoader
        self.generatorFactory = generatorFactory
    }

    func run(projectPath: AbsolutePath) async throws {
        let config = try await configLoader.loadConfig(path: projectPath)
        let generator = generatorFactory.defaultGenerator(config: config)
        let graph = try await generator.load(path: projectPath)
        let lintingErrors = try await graphImplicitLintService.lint(graph: GraphTraverser(graph: graph), config: config)
        lintingErrors.printWarningsIfNeeded()
        if lintingErrors.isEmpty {
            logger.log(level: .info, "Implicit dependencies were not found.")
        }
    }
}
