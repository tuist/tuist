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
    ) async throws -> [LintingIssue]
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
    ) async throws -> [LintingIssue] {
        return try await targetImportsMap(graphTraverser: graphTraverser, inspectType: inspectType)
            .sorted { $0.key.name < $1.key.name }
            .compactMap { target, implicitDependencies in
                guard target.metadata.tags.intersection(ignoreTagsMatching).isEmpty else {
                    return nil
                }
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
        return observedTargetImports
    }

    private func explicitTargetDependencies(graphTraverser: GraphTraverser, target: GraphTarget) -> Set<String> {
        let explicitTargetDependencies = graphTraverser
            .directTargetDependencies(path: target.project.path, name: target.target.name)
            .filter { dependency in
                !dependency.target.bundleId.hasSuffix(".generated.resources")
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
                case .uiTests:
                    switch dependency.target.product {
                    case .app:
                        return false
                    case .staticLibrary, .dynamicLibrary, .framework, .staticFramework, .unitTests, .uiTests, .bundle,
                         .commandLineTool, .tvTopShelfExtension, .appClip, .xpc, .systemExtension, .macro, .appExtension,
                         .stickerPackExtension, .messagesExtension, .extensionKitExtension, .watch2App, .watch2Extension:
                        return true
                    }
                case .staticLibrary, .dynamicLibrary, .framework, .staticFramework, .unitTests, .bundle,
                     .commandLineTool, .tvTopShelfExtension, .appClip, .xpc, .systemExtension, .macro, .appExtension,
                     .stickerPackExtension, .messagesExtension, .extensionKitExtension, .watch2Extension:
                    return true
                }
            }
            .map(\.target.productName)
        return Set(explicitTargetDependencies)
    }
}
