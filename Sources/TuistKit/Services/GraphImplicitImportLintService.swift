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

    func lint(graphTraverser: GraphTraverser, config _: Config) async throws -> [LintingIssue] {
        let allTargets = graphTraverser
            .allTargets()

        let allTargetNames = Set(allTargets.map(\.target.productName))

        var implicitTargetImports: [Target: Set<String>] = [:]
        for project in graphTraverser.projects.values {
            let allTargets = project.targets.values

            for target in allTargets {
                let targetImports = Set(try await targetScanner.imports(for: target))
                let targetTuistDeclaredDependencies = target.dependencies.compactMap {
                    switch $0 {
                    case let .target(name: targetName, _):
                        return project.targets[targetName]?.productName
                    case let .project(target: targetName, path: projectPath, _):
                        return graphTraverser.projects[projectPath]?.targets[targetName]?.productName
                    default:
                        return nil
                    }
                }
                let implicitImports = targetImports.intersection(allTargetNames).subtracting(targetTuistDeclaredDependencies)
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
