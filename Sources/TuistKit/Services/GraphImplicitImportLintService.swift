import Path
import Tools
import TuistCore
import TuistGenerator
import TuistLoader
import XcodeGraph

final class GraphImplicitImportLintService {
    private let targetScanner: TargetImportsScanning

    init(targetScanner: TargetImportsScanning = TargetImportsScanner()) {
        self.targetScanner = targetScanner
    }

    func lint(graphTraverser: GraphTraverser) async throws -> [LintingIssue] {
        let allTargets = graphTraverser
            .allInternalTargets()

        let allTargetNames = Set(allTargets.map(\.target.productName))

        var implicitTargetImports: [Target: Set<String>] = [:]
        for project in graphTraverser.projects.values {
            let allTargets = project.targets.values

            for target in allTargets {
                let sourceDependencies = Set(try await targetScanner.imports(for: target))
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
                let implicitImports = sourceDependencies.intersection(allTargetNames).subtracting(explicitTargetDependencies)
                if !implicitImports.isEmpty {
                    implicitTargetImports[target] = implicitImports
                }
            }
        }
        return implicitTargetImports.map { target, implicitDependencies in
            return LintingIssue(
                reason: "Target \(target.name) implicitly imports \(implicitDependencies.joined(separator: ", ")).",
                severity: .warning
            )
        }
    }
}
