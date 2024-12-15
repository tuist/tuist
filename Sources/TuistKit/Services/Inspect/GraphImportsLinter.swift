import TuistCore
import TuistLoader
import XcodeGraph

enum InspectType {
    case redundant
    case implicit
}

final class GraphImportsLinter {
    private let targetScanner: TargetImportsScanning

    init(targetScanner: TargetImportsScanning = TargetImportsScanner()) {
        self.targetScanner = targetScanner
    }

    func lint(
        graphTraverser: GraphTraverser,
        inspectType: InspectType
    ) async throws -> [LintingIssue] {
        let allInternalTargets = graphTraverser
            .allInternalTargets()
        let allTargets = allInternalTargets
            .union(graphTraverser.allExternalTargets())
            .filter {
                switch inspectType {
                case .redundant:
                    return switch $0.target.product {
                    case .staticLibrary, .staticFramework, .dynamicLibrary, .framework: true
                    default: false
                    }
                case .implicit:
                    return true
                }
            }

        let allTargetNames = Set(allTargets.map(\.target.productName))

        var observedTargetImports: [Target: Set<String>] = [:]
        for target in allInternalTargets {
            let sourceDependencies = Set(try await targetScanner.imports(for: target.target))

            let explicitTargetDependencies = explicitTargetDependencies(
                graphTraverser: graphTraverser,
                target: target
            )

            let observedImports = switch inspectType {
            case .redundant:
                explicitTargetDependencies.subtracting(sourceDependencies)
            case .implicit:
                sourceDependencies.subtracting(explicitTargetDependencies)
                    .intersection(allTargetNames)
            }
            if !observedImports.isEmpty {
                observedTargetImports[target.target] = observedImports
            }
        }
        return observedTargetImports.map { target, implicitDependencies in
            return LintingIssue(
                reason: " - \(target) \(inspectType == .implicit ? "implicitly" : "redundantly") depends on: \(implicitDependencies.joined(separator: ", "))",
                severity: .error
            )
        }
    }

    private func explicitTargetDependencies(
        graphTraverser: GraphTraverser,
        target: GraphTarget
    ) -> Set<String> {
        let targetDependencies = graphTraverser
            .directTargetDependencies(path: target.project.path, name: target.target.name)

        let explicitTargetDependencies = targetDependencies.map { targetDependency in
            if targetDependency.graphTarget.project.type == .external() {
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
}
