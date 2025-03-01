import TuistCore
import TuistLoader
import XcodeGraph

enum InspectType {
    case redundant
    case implicit
}

protocol GraphImportsLinting {
    func lint(
        graphTraverser: GraphTraverser,
        inspectType: InspectType
    ) async throws -> [LintingIssue]
}

final class GraphImportsLinter: GraphImportsLinting {
    private let targetScanner: TargetImportsScanning

    init(targetScanner: TargetImportsScanning = TargetImportsScanner()) {
        self.targetScanner = targetScanner
    }

    func lint(
        graphTraverser: GraphTraverser,
        inspectType: InspectType
    ) async throws -> [LintingIssue] {
        return try await targetImportsMap(
            graphTraverser: graphTraverser,
            inspectType: inspectType
        ).compactMap { target, implicitDependencies in
            return LintingIssue(
                reason: " - \(target.productName) \(inspectType == .implicit ? "implicitly" : "redundantly") depends on: \(implicitDependencies.joined(separator: ", "))",
                severity: .error
            )
        }
    }

    private func targetImportsMap(
        graphTraverser: GraphTraverser,
        inspectType: InspectType
    ) async throws -> [Target: Set<String>] {
        let allInternalTargets = graphTraverser
            .allInternalTargets()
        let allTargets = allInternalTargets
            .union(graphTraverser.allExternalTargets())
            .filter {
                switch inspectType {
                case .redundant:
                    return switch $0.target.product {
                    case .staticLibrary, .staticFramework, .dynamicLibrary, .framework, .app: true
                    default: false
                    }
                case .implicit:
                    return true
                }
            }
        var observedTargetImports: [Target: Set<String>] = [:]

        let allTargetNames = Set(allTargets.map(\.target.productName))

        for target in allInternalTargets {
            let sourceDependencies = Set(try await targetScanner.imports(for: target.target))

            let explicitTargetDependencies = explicitTargetDependencies(
                graphTraverser: graphTraverser,
                target: target,
                externalDependenciesSearch: inspectType == .implicit
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
        return observedTargetImports
    }

    private func explicitTargetDependencies(
        graphTraverser: GraphTraverser,
        target: GraphTarget,
        externalDependenciesSearch: Bool
    ) -> Set<String> {
        let targetDependencies = if externalDependenciesSearch {
            graphTraverser
                .directTargetDependencies(path: target.project.path, name: target.target.name)
        } else {
            graphTraverser
                .directLocalTargetDependencies(path: target.project.path, name: target.target.name)
        }

        let explicitTargetDependencies = targetDependencies.map { targetDependency in
            if case .external = targetDependency.graphTarget.project.type { return graphTraverser
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
