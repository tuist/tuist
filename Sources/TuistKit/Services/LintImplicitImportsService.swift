import Foundation
import Path
import TuistCore
import TuistLoader
import TuistSupport

enum LintImplicitImportsServiceError: FatalError {
    case implicitImportsFound([String])

    public var description: String {
        switch self {
        case let .implicitImportsFound(lintingErrors):
            "Implicit dependencies were found." + "\n" +
                lintingErrors.joined(separator: "\n")
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

    func run(
        path: String?,
        xcode: Bool,
        strict: Bool
    ) async throws {
        let path = try self.path(path)
        let config = try await configLoader.loadConfig(path: path)
        let generator = generatorFactory.defaultGenerator(config: config)
        let graph = try await generator.load(path: path)
        let implicitImports = try await graphImplicitLintService.lint(
            graphTraverser: GraphTraverser(graph: graph),
            config: config
        )

        let lintingErrors = implicitImports.map { target, implicitDependencies in
            if xcode {
                return implicitDependencies.map { implicitImport in
                    "\(implicitImport.file.pathString):\(implicitImport.line): warning: Target \(implicitImport.module) was implicitly imported"
                }
            } else {
                let targetNames = implicitDependencies.map(\.module)
                return [
                    "Target \(target.name) implicitly imports \(targetNames.joined(separator: ", ")).",
                ]
            }
        }
        .flatMap { $0 }

        guard lintingErrors.isEmpty else {
            if strict {
                throw LintImplicitImportsServiceError.implicitImportsFound(lintingErrors)
            } else {
                logger.warning("Implicit dependencies were found.")
                for error in lintingErrors {
                    logger.warning("\(error)")
                }
                return
            }
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
