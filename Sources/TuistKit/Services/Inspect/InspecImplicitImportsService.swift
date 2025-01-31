import Foundation
import Path
import ServiceContextModule
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

final class InspectImplicitImportsService {
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
        let generator = generatorFactory.defaultGenerator(config: config, sources: [])
        let graph = try await generator.load(path: path)
        let issues = try await lint(graphTraverser: GraphTraverser(graph: graph))
        guard issues.isEmpty else {
            throw InspectImplicitImportsServiceError.implicitImportsFound(issues)
        }
        ServiceContext.current?.logger?.log(level: .info, "We did not find any implicit dependencies in your project.")
    }

    private func lint(graphTraverser: GraphTraverser) async throws -> [InspectImplicitImportsServiceErrorIssue] {
        let allInternalTargets = graphTraverser
            .allInternalTargets()
        let allTargets = allInternalTargets.union(graphTraverser.allExternalTargets())

        let allTargetNames = Set(allTargets.map(\.target.productName))

        var implicitTargetImports: [Target: Set<String>] = [:]
        for target in allInternalTargets {
            let sourceDependencies = Set(try await targetScanner.imports(for: target.target))

            let explicitTargetDependencies = explicitTargetDependencies(
                graphTraverser: graphTraverser,
                target: target
            )
            let implicitImports = sourceDependencies.intersection(allTargetNames).subtracting(explicitTargetDependencies)
            if !implicitImports.isEmpty {
                implicitTargetImports[target.target] = implicitImports
            }
        }
        return implicitTargetImports.map { target, implicitDependencies in
            return InspectImplicitImportsServiceErrorIssue(target: target.name, implicitDependencies: implicitDependencies)
        }
    }

    private func explicitTargetDependencies(
        graphTraverser: GraphTraverser,
        target: GraphTarget
    ) -> Set<String> {
        let targetDependencies = graphTraverser
            .directTargetDependencies(path: target.project.path, name: target.target.name)

        let explicitTargetDependencies = targetDependencies.map { targetDependency in
            if case .external = targetDependency.graphTarget.project.type {
                return graphTraverser
                    .allTargetDependencies(path: target.project.path, name: target.target.name)
            } else {
                return Set(arrayLiteral: targetDependency.graphTarget)
            }
        }
        .flatMap { $0 }
        .map(\.target.productName)
        return Set(explicitTargetDependencies)
    }

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
