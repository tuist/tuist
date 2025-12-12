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
        inspectType: InspectType,
        ignoreTagsMatching: Set<String>
    ) async throws -> [InspectImportsIssue]
}

final class GraphImportsLinter: GraphImportsLinting {
    private let targetScanner: TargetImportsScanning

    init(targetScanner: TargetImportsScanning = TargetImportsScanner()) {
        self.targetScanner = targetScanner
    }

    func lint(
        graphTraverser: GraphTraverser,
        inspectType: InspectType,
        ignoreTagsMatching: Set<String>
    ) async throws -> [InspectImportsIssue] {
        return try await targetImportsMap(graphTraverser: graphTraverser, inspectType: inspectType)
            .sorted { $0.key.productName < $1.key.productName }
            .compactMap { target, dependencies in
                guard target.metadata.tags.intersection(ignoreTagsMatching).isEmpty else {
                    return nil
                }
                return InspectImportsIssue(target: target.productName, dependencies: dependencies)
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
                includeExternalDependencies: inspectType == .implicit,
                excludeAppDependenciesForTests: inspectType == .redundant
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
        includeExternalDependencies: Bool,
        excludeAppDependenciesForTests: Bool
    ) -> Set<String> {
        let targetDependencies = if includeExternalDependencies {
            graphTraverser
                .directTargetDependencies(path: target.project.path, name: target.target.name)
        } else {
            graphTraverser
                .directNonExternalTargetDependencies(path: target.project.path, name: target.target.name)
        }

        let explicitTargetDependencies = targetDependencies
            .filter { dependency in
                !dependency.target.bundleId.hasSuffix(".generated.resources")
            }
            .filter { dependency in
                // Macros are referenced by string name in #externalMacro, never via import statements.
                dependency.target.product != .macro
            }
            .filter { dependency in
                switch target.target.product {
                case .app:
                    switch dependency.target.product {
                    case .appExtension, .stickerPackExtension, .messagesExtension, .extensionKitExtension, .watch2App:
                        return false
                    case .app, .staticLibrary, .dynamicLibrary, .framework, .staticFramework, .unitTests, .uiTests, .bundle,
                         .commandLineTool, .watch2Extension, .tvTopShelfExtension, .appClip, .xpc, .systemExtension, .macro:
                        return true
                    }
                case .watch2App:
                    switch dependency.target.product {
                    case .watch2Extension:
                        return false
                    case .app, .staticLibrary, .dynamicLibrary, .framework, .staticFramework, .unitTests, .uiTests, .bundle,
                         .commandLineTool, .tvTopShelfExtension, .appClip, .xpc, .systemExtension, .macro, .appExtension,
                         .stickerPackExtension, .messagesExtension, .extensionKitExtension, .watch2App:
                        return true
                    }
                case .unitTests, .uiTests:
                    switch dependency.target.product {
                    case .app:
                        return !excludeAppDependenciesForTests
                    case .staticLibrary, .dynamicLibrary, .framework, .staticFramework, .unitTests, .uiTests, .bundle,
                         .commandLineTool, .tvTopShelfExtension, .appClip, .xpc, .systemExtension, .macro, .appExtension,
                         .stickerPackExtension, .messagesExtension, .extensionKitExtension, .watch2App, .watch2Extension:
                        return true
                    }
                case .staticLibrary, .dynamicLibrary, .framework, .staticFramework, .bundle,
                     .commandLineTool, .tvTopShelfExtension, .appClip, .xpc, .systemExtension, .macro, .appExtension,
                     .stickerPackExtension, .messagesExtension, .extensionKitExtension, .watch2Extension:
                    return true
                }
            }
            .map { dependency in
                if case .external = dependency.graphTarget.project.type {
                    let targets = [dependency.graphTarget] + graphTraverser.allTargetDependencies(
                        path: dependency.graphTarget.project.path,
                        name: dependency.graphTarget.target.name
                    )
                    return Set(targets)
                } else {
                    return Set(arrayLiteral: dependency.graphTarget)
                }
            }
            .flatMap { $0 }
            .map(\.target.productName)
        return Set(explicitTargetDependencies)
    }
}
