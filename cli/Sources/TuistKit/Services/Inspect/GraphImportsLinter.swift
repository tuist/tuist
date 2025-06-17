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
                includeExternalDependencies: inspectType == .implicit
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
        includeExternalDependencies: Bool
    ) -> Set<String> {
        let targetDependencies = if includeExternalDependencies {
            graphTraverser
                .directTargetDependencies(path: target.project.path, name: target.target.name)
        } else {
            graphTraverser
                .directLocalTargetDependencies(path: target.project.path, name: target.target.name)
        }

        let explicitTargetDependencies = targetDependencies
            .filter { dependency in
                !dependency.target.bundleId.hasSuffix(".generated.resources")
            }
            .filter { dependency in
                !(target.target.product == .uiTests && dependency.target.product == .app)
            }
            .filter { dependency in
                // App targets depending on extensions are not redundant imports
                guard target.target.product == .app || target.target.product == .watch2App else { return true }
                switch dependency.target.product {
                case .appExtension, .stickerPackExtension, .messagesExtension, .extensionKitExtension, .watch2App:
                    return false
                case .app, .staticLibrary, .dynamicLibrary, .framework, .staticFramework, .unitTests, .uiTests, .bundle,
                     .commandLineTool, .watch2Extension, .tvTopShelfExtension, .appClip, .xpc, .systemExtension, .macro:
                    return true
                }
            }
            .map { dependency in
                if case .external = dependency.graphTarget.project.type { return graphTraverser
                    .allTargetDependencies(path: target.project.path, name: target.target.name)
                } else {
                    return Set(arrayLiteral: dependency.graphTarget)
                }
            }
            .flatMap { $0 }
            .map(\.target.productName)
        return Set(explicitTargetDependencies)
    }
}
