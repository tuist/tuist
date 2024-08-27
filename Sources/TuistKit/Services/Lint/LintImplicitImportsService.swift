import Foundation
import Path
import TuistCore
import TuistLoader
import TuistSupport
import XcodeGraph

struct LintImplicitImportsServiceErrorIssue: Equatable {
    let target: String
    let implicitDependencies: Set<String>
}

enum LintImplicitImportsServiceError: FatalError, Equatable {
    case implicitImportsFound([LintImplicitImportsServiceErrorIssue])

    public var description: String {
        switch self {
        case let .implicitImportsFound(issues):
            """
            The following implicit dependencies were found:
            \(
                issues.map { " - \($0.target) implicitly depends on: \($0.implicitDependencies.joined(separator: ", "))" }
                    .joined(separator: "\n")
            )
            """
        }
    }

    var type: ErrorType {
        .abort
    }
}

final class LintImplicitImportsService {
    private let configLoader: ConfigLoading
    private let generatorFactory: GeneratorFactorying
    private let targetScanner: TargetImportsScanning

    init(
        generatorFactory: GeneratorFactorying = GeneratorFactory(),
        configLoader: ConfigLoading = ConfigLoader(),
        targetScanner: TargetImportsScanning = TargetImportsScanner()
    ) {
        self.configLoader = configLoader
        self.generatorFactory = generatorFactory
        self.targetScanner = targetScanner
    }

    func run(path: String?) async throws {
        let path = try self.path(path)
        let config = try await configLoader.loadConfig(path: path)
        let generator = generatorFactory.defaultGenerator(config: config)
        let graph = try await generator.load(path: path)
        let issues = try await lint(graphTraverser: GraphTraverser(graph: graph))
        guard issues.isEmpty else {
            throw LintImplicitImportsServiceError.implicitImportsFound(issues)
        }
        logger.log(level: .info, "We did not find any implicit dependencies in your project.")
    }

    private func lint(graphTraverser: GraphTraverser) async throws -> [LintImplicitImportsServiceErrorIssue] {
        let allTargets = graphTraverser
            .allInternalTargets()

        let allTargetNames = Set(allTargets.map(\.target.productName))

        var implicitTargetImports: [Target: Set<String>] = [:]
        for project in graphTraverser.projects.values {
            let allTargets = project.targets.values

            for target in allTargets {
                let sourceDependencies = Set(try await targetScanner.imports(for: target))
                let explicitTargetDependencies = graphTraverser
                    .directTargetDependencies(path: project.path, name: target.name)
                    .map(\.graphTarget.target.productName)
                let implicitImports = sourceDependencies.intersection(allTargetNames).subtracting(explicitTargetDependencies)
                if !implicitImports.isEmpty {
                    implicitTargetImports[target] = implicitImports
                }
            }
        }
        return implicitTargetImports.map { target, implicitDependencies in
            return LintImplicitImportsServiceErrorIssue(target: target.name, implicitDependencies: implicitDependencies)
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
