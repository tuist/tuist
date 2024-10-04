import Foundation
import Path
import TuistCore
import TuistLoader
import TuistSupport
import XcodeGraph

struct InspectImportsServiceErrorIssue: Equatable {
    let target: String
    let implicitDependencies: Set<String>
}

enum InspectRedundantImportsServiceError: FatalError, Equatable {
    case redundantImportsFound([InspectImportsServiceErrorIssue])

    public var description: String {
        switch self {
        case let .redundantImportsFound(issues):
            """
            The following redundant dependencies were found:
            \(
                issues.map { " - \($0.target) redundantly depends on: \($0.implicitDependencies.joined(separator: ", "))" }
                    .joined(separator: "\n")
            )
            """
        }
    }

    var type: ErrorType {
        .abort
    }
}

enum InspectImplicitImportsServiceError: FatalError, Equatable {
    case implicitImportsFound([InspectImportsServiceErrorIssue])

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

enum InspectType {
    case redundant
    case implicit
}

final class InspectImportsService {
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

    func run(
        path: String?,
        inspectType: InspectType
    ) async throws {
        let path = try self.path(path)
        let config = try await configLoader.loadConfig(path: path)
        let generator = generatorFactory.defaultGenerator(config: config, sources: [])
        let graph = try await generator.load(path: path)
        let issues = try await lint(graphTraverser: GraphTraverser(graph: graph), inspectType: inspectType)
        guard issues.isEmpty else {
            switch inspectType {
            case .redundant:
                throw InspectRedundantImportsServiceError.redundantImportsFound(issues)
            case .implicit:
                throw InspectImplicitImportsServiceError.implicitImportsFound(issues)
            }
        }
        logger.log(
            level: .info,
            "We did not find any \(inspectType == .implicit ? "implicit" : "redundant") dependencies in your project."
        )
    }

    private func lint(
        graphTraverser: GraphTraverser,
        inspectType: InspectType
    ) async throws -> [InspectImportsServiceErrorIssue] {
        var allTargets = graphTraverser
            .allInternalTargets()

        if inspectType == .redundant {
            allTargets = allTargets.filter {
                switch $0.target.product {
                case .staticLibrary, .staticFramework, .dynamicLibrary, .framework: true
                default: false
                }
            }
        }

        let allTargetNames = Set(allTargets.map(\.target.productName))

        var observedTargetImports: [Target: Set<String>] = [:]
        for project in graphTraverser.projects.values {
            let allTargets = project.targets.values

            for target in allTargets {
                let sourceDependencies = Set(try await targetScanner.imports(for: target))
                let explicitTargetDependencies = Set(
                    graphTraverser
                        .directTargetDependencies(path: project.path, name: target.name)
                        .map(\.graphTarget.target.productName)
                )

                var imports = switch inspectType {
                case .redundant:
                    explicitTargetDependencies.subtracting(sourceDependencies)
                case .implicit:
                    sourceDependencies.subtracting(explicitTargetDependencies)
                }
                imports = imports.intersection(allTargetNames)

                if !imports.isEmpty {
                    observedTargetImports[target] = imports
                }
            }
        }
        return observedTargetImports.map { target, implicitDependencies in
            return InspectImportsServiceErrorIssue(target: target.name, implicitDependencies: implicitDependencies)
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
