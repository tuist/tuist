import Path
import Tools
import TuistCore
import TuistGenerator
import TuistLoader
import XcodeGraph

final class GraphImplicitImportLintService {
    let targetScanner: TargetImportsScanning

    init(targetScanner: TargetImportsScanning = TargetImportsScanner()) {
        self.targetScanner = targetScanner
    }

    func lint(graphTraverser: GraphTraverser, config _: Config) async throws -> [Target: [FileImport]] {
        let allTargets = graphTraverser
            .allInternalTargets()

        let allTargetNames = Set(allTargets.map(\.target.productName))

        var implicitTargetImports: [Target: [FileImport]] = [:]
        for project in graphTraverser.projects.values {
            let allTargets = project.targets.values

            for target in allTargets {
                let sourceDependencies = try await targetScanner.imports(for: target)
                let explicitTargetDependencies = target.dependencies.compactMap {
                    switch $0 {
                    case let .target(name: targetName, _):
                        return project.targets[targetName]?.productName
                    case let .project(target: targetName, path: projectPath, _):
                        return graphTraverser.projects[projectPath]?.targets[targetName]?.productName
                    default:
                        return nil
                    }
                }

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
}
