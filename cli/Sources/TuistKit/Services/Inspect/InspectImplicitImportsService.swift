import Foundation
import Path
import TuistCore
import TuistLoader
import TuistSupport
import XcodeGraph

struct InspectImplicitImportsServiceErrorIssue: Equatable {
    let target: String
    let implicitDependencies: Set<String>
}

enum InspectImplicitImportsServiceError: FatalError, Equatable {
    case implicitImportsFound([InspectImplicitImportsServiceErrorIssue])

    var description: String {
        switch self {
        case let .implicitImportsFound(issues):
            """
            The following implicit dependencies were found:
            \(
                issues.map { " - \($0.target) implicitly depends on: \($0.implicitDependencies.sorted().joined(separator: ", "))" }
                    .joined(separator: "\n")
            )
            """
        }
    }

    var type: ErrorType {
        .abort
    }
}

final class InspectImplicitImportsService {
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
            inspectType: .implicit,
            ignoreTagsMatching: []
        )
        if !issues.isEmpty {
            Logger.current.log(
                level: .info,
                "The following implicit dependencies were found:"
            )
            try issues.printAndThrowErrorsIfNeeded()
        }
        Logger.current.log(
            level: .info,
            "We did not find any implicit dependencies in your project."
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
