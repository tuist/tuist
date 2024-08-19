import Foundation
import Path
import TuistCore
import TuistLoader
import TuistSupport

enum LintImplicitImportsServiceError: FatalError {
    case implicitImportsFound([LintingIssue])

    public var description: String {
        switch self {
        case let .implicitImportsFound(lintingErrors):
            "Implicit dependencies were found." + "\n" +
                lintingErrors.map(\.reason).joined(separator: "\n")
        }
    }

    var type: ErrorType {
        .abort
    }
}

final class LintImplicitImportsService {
    private let graphImplicitLintService: GraphImplicitImportLintService
    private let configLoader: ConfigLoading
    private let generatorFactory: GeneratorFactorying

    init(
        graphImplicitLintService: GraphImplicitImportLintService = GraphImplicitImportLintService(),
        generatorFactory: GeneratorFactorying = GeneratorFactory(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.graphImplicitLintService = graphImplicitLintService
        self.configLoader = configLoader
        self.generatorFactory = generatorFactory
    }

    func run(path: String?) async throws {
        let path = try self.path(path)
        let config = try await configLoader.loadConfig(path: path)
        let generator = generatorFactory.defaultGenerator(config: config)
        let graph = try await generator.load(path: path)
        let lintingErrors = try await graphImplicitLintService.lint(graphTraverser: GraphTraverser(graph: graph), config: config)
        guard lintingErrors.isEmpty else {
            throw LintImplicitImportsServiceError.implicitImportsFound(lintingErrors)
        }
        logger.log(level: .info, "We did not find any implicit dependencies in your project.")
    }

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
