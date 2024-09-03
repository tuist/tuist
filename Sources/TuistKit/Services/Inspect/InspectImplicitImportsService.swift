import Foundation
import Path
import TuistCore
import TuistLoader
import TuistSupport
import XcodeGraph

enum InspectImplicitImportsServiceError: FatalError, Equatable {
    case implicitImportsFound([String])

    public var description: String {
        switch self {
        case let .implicitImportsFound(issues):
            """
            The following implicit dependencies were found:
            \(issues.joined(separator: "\n"))
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

    func run(
        path: String?,
        xcode: Bool,
        strict: Bool
    ) async throws {
        let path = try self.path(path)
        let config = try await configLoader.loadConfig(path: path)
        let generator = generatorFactory.defaultGenerator(config: config, sources: [])
        let graph = try await generator.load(path: path)
        let implicitImports = try await lint(graphTraverser: GraphTraverser(graph: graph))
        let issues = implicitImports.map { target, implicitDependencies in
            if xcode {
                return implicitDependencies.map { implicitImport in
                    "\(implicitImport.file.pathString):\(implicitImport.line): warning: Target \(implicitImport.module) was implicitly imported"
                }
            } else {
                let targetNames = implicitDependencies.map(\.module)
                return [
                    " - \(target.name) implicitly depends on: \(targetNames.joined(separator: ", "))",
                ]
            }
        }
        .flatMap { $0 }

        guard issues.isEmpty else {
            if strict {
                throw InspectImplicitImportsServiceError.implicitImportsFound(issues)
            } else {
                logger.warning("The following implicit dependencies were found:")
                for issue in issues {
                    logger.warning("\(issue)")
                }
                return
            }
        }
        logger.log(level: .info, "We did not find any implicit dependencies in your project.")
    }

    private func lint(graphTraverser: GraphTraverser) async throws -> [Target: [ModuleImport]] {
        let allTargets = graphTraverser
            .allInternalTargets()

        let allTargetNames = Set(allTargets.map(\.target.productName))

        var implicitTargetImports: [Target: [ModuleImport]] = [:]
        for project in graphTraverser.projects.values {
            let allTargets = project.targets.values

            for target in allTargets {
                let sourceDependencies = try await targetScanner.imports(for: target)
                let explicitTargetDependencies = graphTraverser
                    .directTargetDependencies(path: project.path, name: target.name)
                    .map(\.graphTarget.target.productName)
                let implicitImports = sourceDependencies
                    .filter {
                        allTargetNames.contains($0.module) && !explicitTargetDependencies.contains($0.module)
                    }
                if !implicitImports.isEmpty {
                    implicitTargetImports[target] = implicitImports
                }
            }
        }
        return implicitTargetImports
    }

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
