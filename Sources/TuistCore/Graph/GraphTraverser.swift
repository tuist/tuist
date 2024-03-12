import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

// swiftlint:disable type_body_length
public class GraphTraverser: GraphTraversing {
    public var name: String { graph.name }
    public var hasPackages: Bool { !graph.packages.flatMap(\.value).isEmpty }
    public var path: AbsolutePath { graph.path }
    public var workspace: Workspace { graph.workspace }
    public var projects: [AbsolutePath: Project] { graph.projects }
    public var targets: [AbsolutePath: [String: Target]] { graph.targets }
    public var dependencies: [GraphDependency: Set<GraphDependency>] { graph.dependencies }

    private let graph: Graph
    private let conditionCache = ConditionCache()
    private let systemFrameworkMetadataProvider: SystemFrameworkMetadataProviding = SystemFrameworkMetadataProvider()

    public required init(graph: Graph) {
        self.graph = graph
    }

    public var hasRemotePackages: Bool {
        graph.packages.values.flatMap(\.values).first(where: {
            switch $0 {
            case .remote: return true
            case .local: return false
            }
        }) != nil
    }

    public func rootTargets() -> Set<GraphTarget> {
        Set(graph.workspace.projects.reduce(into: Set()) { result, path in
            result.formUnion(targets(at: path))
        })
    }

    public func allTargets() -> Set<GraphTarget> {
        allTargets(excludingExternalTargets: false)
    }

    public func allTargetsTopologicalSorted() throws -> [GraphTarget] {
        try topologicalSort(
            Array(allTargets()),
            successors: {
                directTargetDependencies(path: $0.path, name: $0.target.name).map(\.graphTarget)
            }
        ).reversed()
    }

    public func allInternalTargets() -> Set<GraphTarget> {
        allTargets(excludingExternalTargets: true)
    }

    public func allTestPlans() -> Set<TestPlan> {
        Set(schemes().flatMap { $0.testAction?.testPlans ?? [] })
    }

    public func rootProjects() -> Set<Project> {
        Set(graph.workspace.projects.compactMap {
            projects[$0]
        })
    }

    public func schemes() -> [Scheme] {
        projects.values.flatMap(\.schemes) + graph.workspace.schemes
    }

    public func precompiledFrameworksPaths() -> Set<AbsolutePath> {
        let dependencies = graph.dependencies.reduce(into: Set<GraphDependency>()) { acc, next in
            acc.formUnion([next.key])
            acc.formUnion(next.value)
        }
        return Set(dependencies.compactMap { dependency -> AbsolutePath? in
            guard case let GraphDependency.framework(path, _, _, _, _, _, _) = dependency else { return nil }
            return path
        })
    }

    public func targets(product: Product) -> Set<GraphTarget> {
        var filteredTargets: Set<GraphTarget> = Set()
        for (path, projectTargets) in targets {
            projectTargets.values.forEach { target in
                guard target.product == product else { return }
                guard let project = projects[path] else { return }
                filteredTargets.formUnion([GraphTarget(path: path, target: target, project: project)])
            }
        }
        return filteredTargets
    }

    public func target(path: AbsolutePath, name: String) -> GraphTarget? {
        guard let project = graph.projects[path], let target = graph.targets[path]?[name] else { return nil }
        return GraphTarget(path: path, target: target, project: project)
    }

    public func targets(at path: AbsolutePath) -> Set<GraphTarget> {
        guard let project = graph.projects[path] else { return Set() }
        guard let targets = graph.targets[path] else { return [] }
        return Set(targets.values.map { GraphTarget(path: path, target: $0, project: project) })
    }

    public func testPlan(name: String) -> TestPlan? {
        allTestPlans().first { $0.name == name }
    }

    public func allTargetDependencies(path: AbsolutePath, name: String) -> Set<GraphTarget> {
        guard let target = target(path: path, name: name) else { return [] }
        return transitiveClosure([target]) { target in
            Array(
                directTargetDependencies(
                    path: target.path,
                    name: target.target.name
                )
            ).map(\.graphTarget)
        }
    }

    public func directTargetDependencies(path: AbsolutePath, name: String) -> Set<GraphTargetReference> {
        let target = GraphDependency.target(name: name, path: path)
        guard let dependencies = graph.dependencies[target]
        else { return [] }

        let targetDependencies = dependencies
            .compactMap(\.targetDependency)

        return Set(convertToGraphTargetReferences(targetDependencies, for: target))
    }

    public func directLocalTargetDependencies(path: AbsolutePath, name: String) -> Set<GraphTargetReference> {
        let target = GraphDependency.target(name: name, path: path)
        guard let dependencies = graph.dependencies[target],
              graph.projects[path] != nil
        else { return [] }

        let localTargetDependencies = dependencies
            .compactMap(\.targetDependency)
            .filter { $0.path == path }

        return Set(convertToGraphTargetReferences(localTargetDependencies, for: target))
    }

    func convertToGraphTargetReferences(
        _ dependencies: [(name: String, path: AbsolutePath)],
        for target: GraphDependency
    ) -> [GraphTargetReference] {
        dependencies.compactMap { dependencyName, dependencyPath -> GraphTargetReference? in
            guard let projectDependencies = graph.targets[dependencyPath],
                  let dependencyTarget = projectDependencies[dependencyName],
                  let dependencyProject = graph.projects[dependencyPath]
            else {
                return nil
            }
            let condition = graph.dependencyConditions[(target, .target(name: dependencyTarget.name, path: dependencyPath))]
            let graphTarget = GraphTarget(path: dependencyPath, target: dependencyTarget, project: dependencyProject)
            return GraphTargetReference(target: graphTarget, condition: condition)
        }
    }

    public func resourceBundleDependencies(path: AbsolutePath, name: String) -> Set<GraphDependencyReference> {
        guard let target = graph.targets[path]?[name] else { return [] }
        guard target.supportsResources else { return [] }

        let canHostResources: (GraphDependency) -> Bool = {
            self.target(from: $0)?.target.supportsResources == true
        }

        let bundles = filterDependencies(
            from: .target(name: name, path: path),
            test: isDependencyResourceBundle,
            skip: canHostResources
        )

        return Set(bundles.compactMap { dependencyReference(to: $0, from: .target(name: name, path: path)) })
    }

    public func target(from dependency: GraphDependency) -> GraphTarget? {
        guard case let GraphDependency.target(name, path) = dependency else {
            return nil
        }
        guard let target = graph.targets[path]?[name] else { return nil }
        guard let project = graph.projects[path] else { return nil }
        return GraphTarget(path: path, target: target, project: project)
    }

    public func appExtensionDependencies(path: AbsolutePath, name: String) -> Set<GraphTargetReference> {
        let validProducts: [Product] = [
            .appExtension, .stickerPackExtension, .watch2Extension, .tvTopShelfExtension, .messagesExtension,
        ]
        return Set(
            directLocalTargetDependencies(path: path, name: name)
                .filter { validProducts.contains($0.target.product) }
        )
    }

    public func extensionKitExtensionDependencies(path: TSCBasic.AbsolutePath, name: String) -> Set<GraphTargetReference> {
        let validProducts: [Product] = [
            .extensionKitExtension,
        ]
        return Set(
            directLocalTargetDependencies(path: path, name: name)
                .filter { validProducts.contains($0.target.product) }
        )
    }

    public func appClipDependencies(path: AbsolutePath, name: String) -> GraphTargetReference? {
        directLocalTargetDependencies(path: path, name: name)
            .first { $0.target.product == .appClip }
    }

    public func buildsForMacCatalyst(path: AbsolutePath, name: String) -> Bool {
        guard target(path: path, name: name)?.target.supportsCatalyst ?? false else {
            return false
        }
        return allDependenciesSatisfy(from: .target(name: name, path: path)) { dependency in
            if let target = self.target(from: dependency) {
                return target.target.supportsCatalyst
            } else {
                // TODO: - Obtain this information from pre-compiled binaries
                // lipo -info should include "macabi" in the list of architectures
                return false
            }
        }
    }

    // Filter based on edges
    public func directStaticDependencies(path: AbsolutePath, name: String) -> Set<GraphDependencyReference> {
        Set(
            graph.dependencies[.target(name: name, path: path)]?
                .compactMap { (dependency: GraphDependency) -> GraphDependencyReference? in
                    guard case let GraphDependency.target(dependencyName, dependencyPath) = dependency,
                          let target = graph.targets[dependencyPath]?[dependencyName],
                          target.product.isStatic
                    else {
                        return nil
                    }

                    return dependencyReference(
                        to: .target(name: dependencyName, path: dependencyPath),
                        from: .target(name: name, path: path)
                    )
                }
                ?? []
        )
    }

    public func embeddableFrameworks(path: AbsolutePath, name: String) -> Set<GraphDependencyReference> {
        guard let target = target(path: path, name: name), canEmbedProducts(target: target.target) else { return Set() }

        var references: Set<GraphDependencyReference> = Set([])

        /// Precompiled frameworks
        var precompiledFrameworks = filterDependencies(
            from: .target(name: name, path: path),
            test: { $0.isPrecompiledDynamicAndLinkable },
            skip: or(canDependencyEmbedProducts, isDependencyPrecompiledMacro)
        )
        // Skip merged precompiled libraries from merging into the runnable binary
        if case let .manual(dependenciesToMerge) = target.target.mergedBinaryType {
            precompiledFrameworks = precompiledFrameworks
                .filter { !isXCFrameworkMerged(dependency: $0, expectedMergedBinaries: dependenciesToMerge) }
        }
        references.formUnion(precompiledFrameworks.lazy.compactMap { self.dependencyReference(
            to: $0,
            from: .target(name: name, path: path)
        ) })

        /// Other targets' frameworks.
        var otherTargetFrameworks = filterDependencies(
            from: .target(name: name, path: path),
            test: isDependencyDynamicTarget,
            skip: canDependencyEmbedProducts
        )

        if target.target.mergedBinaryType != .disabled {
            otherTargetFrameworks = otherTargetFrameworks.filter(isDependencyDynamicNonMergeableTarget)
        }

        references.formUnion(otherTargetFrameworks.lazy.compactMap { self.dependencyReference(
            to: $0,
            from: .target(name: name, path: path)
        ) })

        // Exclude any products embed in unit test host apps
        if target.target.product == .unitTests {
            if let hostApp = unitTestHost(path: path, name: name) {
                references.subtract(embeddableFrameworks(path: hostApp.path, name: hostApp.target.name))
            } else {
                references = Set()
            }
        }

        return references
    }

    public func searchablePathDependencies(path: AbsolutePath, name: String) throws -> Set<GraphDependencyReference> {
        try linkableDependencies(path: path, name: name, shouldExcludeHostAppDependencies: false)
            .union(staticPrecompiledFrameworksDependencies(path: path, name: name))
    }

    public func linkableDependencies(path: AbsolutePath, name: String) throws -> Set<GraphDependencyReference> {
        try linkableDependencies(path: path, name: name, shouldExcludeHostAppDependencies: true)
    }

    // swiftlint:disable:next function_body_length
    public func linkableDependencies(
        path: AbsolutePath,
        name: String,
        shouldExcludeHostAppDependencies: Bool
    ) throws -> Set<GraphDependencyReference> {
        guard let target = target(path: path, name: name) else { return Set() }

        var references = Set<GraphDependencyReference>()
        let targetGraphDependency = GraphDependency.target(name: name, path: path)

        // System libraries and frameworks
        if target.target.canLinkStaticProducts() {
            let transitiveSystemLibraries = transitiveStaticDependencies(from: targetGraphDependency)
                .flatMap { dependency -> [GraphDependencyReference] in
                    let dependencies = self.graph.dependencies[dependency, default: []]
                    return dependencies.compactMap { dependencyDependency -> GraphDependencyReference? in
                        guard case GraphDependency.sdk = dependencyDependency else { return nil }
                        return dependencyReference(to: dependencyDependency, from: targetGraphDependency)
                    }
                }
            references.formUnion(transitiveSystemLibraries)
        }

        // AppClip dependencies
        if target.target.isAppClip {
            let path = try systemFrameworkMetadataProvider.loadMetadata(
                sdkName: "AppClip.framework",
                status: .required,
                platform: .iOS,
                source: .system
            )
            .path
            references.formUnion([GraphDependencyReference.sdk(
                path: path,
                status: .required,
                source: .system,
                condition: .when([.ios])
            )])
        }

        // Direct system libraries and frameworks
        let directSystemLibrariesAndFrameworks = graph.dependencies[targetGraphDependency, default: []]
            .compactMap { dependency -> GraphDependencyReference? in
                guard case GraphDependency.sdk = dependency else { return nil }
                return dependencyReference(to: dependency, from: targetGraphDependency)
            }
        references.formUnion(directSystemLibrariesAndFrameworks)

        // Precompiled libraries and frameworks
        let precompiled = graph.dependencies[.target(name: name, path: path), default: []]
            .lazy
            .filter(\.isPrecompiled)

        let precompiledDependencies = precompiled
            .flatMap { filterDependencies(from: $0)
            }

        let precompiledLibrariesAndFrameworks = Set(precompiled + precompiledDependencies)
            .filter(\.isPrecompiledDynamicAndLinkable)
            .compactMap { dependencyReference(to: $0, from: targetGraphDependency) }

        references.formUnion(precompiledLibrariesAndFrameworks)

        // Static libraries and frameworks / Static libraries' dynamic libraries
        if target.target.canLinkStaticProducts() {
            let transitiveStaticTargetReferences = transitiveStaticDependencies(from: targetGraphDependency)

            // Exclude any static products linked in a host application
            // however, for search paths it's fine to keep them included
            let hostApplicationStaticTargets: Set<GraphDependency>
            if target.target.product == .unitTests, shouldExcludeHostAppDependencies,
               let hostApp = unitTestHost(path: path, name: name)
            {
                hostApplicationStaticTargets =
                    transitiveStaticDependencies(from: .target(name: hostApp.target.name, path: hostApp.project.path))
            } else {
                hostApplicationStaticTargets = Set()
            }

            let staticDependenciesDynamicLibrariesAndFrameworks = transitiveStaticTargetReferences.flatMap { dependency in
                self.graph.dependencies[dependency, default: []]
                    .lazy
                    .filter(\.isTarget)
                    .filter(isDependencyDynamicTarget)
            }

            let staticDependenciesPrecompiledLibrariesAndFrameworks = transitiveStaticTargetReferences.flatMap { dependency in
                self.graph.dependencies[dependency, default: []]
                    .lazy
                    .filter { $0.isPrecompiled && $0.isLinkable }
            }

            let allDependencies = (
                transitiveStaticTargetReferences
                    + staticDependenciesDynamicLibrariesAndFrameworks
                    + staticDependenciesPrecompiledLibrariesAndFrameworks
            )

            references.formUnion(
                allDependencies
                    .compactMap { dependencyReference(to: $0, from: targetGraphDependency) }
            )
            references.subtract(
                hostApplicationStaticTargets
                    .compactMap { dependencyReference(to: $0, from: targetGraphDependency) }
            )
        }

        // Link dynamic libraries and frameworks
        let dynamicLibrariesAndFrameworks = graph.dependencies[.target(name: name, path: path), default: []]
            .filter(or(isDependencyDynamicLibrary, isDependencyFramework))
            .compactMap { dependencyReference(to: $0, from: targetGraphDependency) }

        references.formUnion(dynamicLibrariesAndFrameworks)

        return references
    }

    public func copyProductDependencies(path: AbsolutePath, name: String) -> Set<GraphDependencyReference> {
        guard let target = target(path: path, name: name) else { return Set() }

        var dependencies = Set<GraphDependencyReference>()

        if target.target.product.isStatic {
            dependencies.formUnion(directStaticDependencies(path: path, name: name))
            dependencies.formUnion(staticPrecompiledXCFrameworksDependencies(path: path, name: name))
        }

        dependencies.formUnion(resourceBundleDependencies(path: path, name: name))

        return Set(dependencies)
    }

    public func directSwiftMacroExecutables(path: AbsolutePath, name: String) -> Set<GraphDependencyReference> {
        let dependencies = directTargetDependencies(path: path, name: name)
            .filter { $0.target.product == .macro }
            .map { GraphDependencyReference.product(
                target: $0.target.name,
                productName: $0.target.productName,
                condition: .when([.macos])
            ) }

        return Set(dependencies)
    }

    public func directSwiftMacroTargets(path: AbsolutePath, name: String) -> Set<GraphTargetReference> {
        let dependencies = directTargetDependencies(path: path, name: name)
            .filter { [.staticFramework, .framework, .dynamicLibrary, .staticLibrary].contains($0.target.product) }
            .filter { self.directSwiftMacroExecutables(path: $0.graphTarget.path, name: $0.graphTarget.target.name).count != 0 }
        return Set(dependencies)
    }

    public func allSwiftMacroTargets(path: AbsolutePath, name: String) -> Set<GraphTarget> {
        var dependencies = allTargetDependencies(path: path, name: name)
            .filter { [.staticFramework, .framework, .dynamicLibrary, .staticLibrary].contains($0.target.product) }
            .filter { self.directSwiftMacroExecutables(path: $0.path, name: $0.target.name).count != 0 }

        if let target = target(path: path, name: name), !directSwiftMacroExecutables(path: path, name: name).isEmpty {
            dependencies.insert(target)
        }

        return Set(dependencies)
    }

    public func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        let dependencies = graph.dependencies[.target(name: name, path: path), default: []]
        let libraryPublicHeaders = dependencies.compactMap { dependency -> AbsolutePath? in
            guard case let GraphDependency.library(_, publicHeaders, _, _, _) = dependency else { return nil }
            return publicHeaders
        }
        return Set(libraryPublicHeaders)
    }

    public func librariesSearchPaths(path: AbsolutePath, name: String) throws -> Set<AbsolutePath> {
        let directDependencies = graph.dependencies[.target(name: name, path: path), default: []]
        let directDependenciesLibraryPaths = directDependencies.compactMap { dependency -> AbsolutePath? in
            guard case let GraphDependency.library(path, _, _, _, _) = dependency else { return nil }
            return path
        }

        // In addition to any directly linked libraries, search paths for any transitivley linked libraries
        // are also needed.
        let linkedLibraryPaths: [AbsolutePath] = try linkableDependencies(
            path: path,
            name: name,
            shouldExcludeHostAppDependencies: false
        ).compactMap { dependency in
            switch dependency {
            case let .library(path: path, linking: _, architectures: _, product: _, condition: _):
                return path
            default:
                return nil
            }
        }

        return Set((directDependenciesLibraryPaths + linkedLibraryPaths).compactMap { $0.removingLastComponent() })
    }

    public func librariesSwiftIncludePaths(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        let dependencies = graph.dependencies[.target(name: name, path: path), default: []]
        let librarySwiftModuleMapPaths = dependencies.compactMap { dependency -> AbsolutePath? in
            guard case let GraphDependency.library(_, _, _, _, swiftModuleMapPath) = dependency else { return nil }
            return swiftModuleMapPath
        }
        return Set(librarySwiftModuleMapPaths.compactMap { $0.removingLastComponent() })
    }

    public func runPathSearchPaths(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        guard let target = target(path: path, name: name),
              canEmbedProducts(target: target.target),
              target.target.product == .unitTests,
              unitTestHost(path: path, name: name) == nil
        else {
            return Set()
        }

        var references: Set<AbsolutePath> = Set([])

        let from = GraphDependency.target(name: name, path: path)
        let precompiledFrameworksPaths = filterDependencies(
            from: from,
            test: { $0.isPrecompiledDynamicAndLinkable },
            skip: canDependencyEmbedProducts
        )
        .lazy
        .compactMap { (dependency: GraphDependency) -> AbsolutePath? in
            switch dependency {
            case let .xcframework(xcframework): return xcframework.path
            case let .framework(path, _, _, _, _, _, _): return path
            case .macro: return nil
            case .library: return nil
            case .bundle: return nil
            case .packageProduct: return nil
            case .target: return nil
            case .sdk: return nil
            }
        }
        .map(\.parentDirectory)

        references.formUnion(precompiledFrameworksPaths)
        return references
    }

    public func hostTargetFor(path: AbsolutePath, name: String) -> GraphTarget? {
        guard let targets = graph.targets[path] else { return nil }
        guard let project = graph.projects[path] else { return nil }

        return targets.values.compactMap { target -> GraphTarget? in
            let dependencies = self.graph.dependencies[.target(name: target.name, path: path), default: Set()]
            let dependsOnTarget = dependencies.contains(where: { dependency in
                // swiftlint:disable:next identifier_name
                guard case let GraphDependency.target(_name, _path) = dependency else { return false }
                return _name == name && _path == path
            })
            let graphTarget = GraphTarget(path: path, target: target, project: project)
            return dependsOnTarget ? graphTarget : nil
        }.first
    }

    public func allProjectDependencies(path: AbsolutePath) throws -> Set<GraphDependencyReference> {
        let targets = targets(at: path)
        if targets.isEmpty { return Set() }
        var references: Set<GraphDependencyReference> = Set()

        // Linkable dependencies
        for target in targets {
            try references.formUnion(linkableDependencies(path: path, name: target.target.name))
            references.formUnion(embeddableFrameworks(path: path, name: target.target.name))
            references.formUnion(copyProductDependencies(path: path, name: target.target.name))
        }
        return references
    }

    public func dependsOnXCTest(path: AbsolutePath, name: String) -> Bool {
        guard let target = target(path: path, name: name) else {
            return false
        }
        if target.target.product.testsBundle {
            return true
        }
        if target.target.settings?.base["ENABLE_TESTING_SEARCH_PATHS"] == "YES" {
            return true
        }
        guard let directDependencies = dependencies[.target(name: name, path: path)] else {
            return false
        }
        return directDependencies.contains(where: { dependency in
            switch dependency {
            case .sdk(name: "XCTest", path: _, status: _, source: _):
                return true
            default:
                return false
            }
        })
    }

    public func prebuiltDependencies(for rootDependency: GraphDependency) -> Set<GraphDependency> {
        filterDependencies(
            from: rootDependency,
            test: \.isPrecompiled
        )
    }

    public func targetsWithExternalDependencies() -> Set<GraphTarget> {
        allInternalTargets().filter { directTargetExternalDependencies(path: $0.path, name: $0.target.name).count != 0 }
    }

    public func directTargetExternalDependencies(path: AbsolutePath, name: String) -> Set<GraphTargetReference> {
        directTargetDependencies(path: path, name: name).filter(\.graphTarget.project.isExternal)
    }

    public func allExternalTargets() -> Set<GraphTarget> {
        Set(graph.projects.compactMap { path, project in
            project.isExternal ? (path, project) : nil
        }.flatMap { projectPath, project in
            let targets = graph.targets[projectPath, default: [:]].values
            return targets.map { GraphTarget(path: projectPath, target: $0, project: project) }
        })
    }

    public func allOrphanExternalTargets() -> Set<GraphTarget> {
        let graphDependenciesWithExternalDependencies = Set(
            targetsWithExternalDependencies()
                .map { GraphDependency.target(name: $0.target.name, path: $0.project.path) }
        )

        let allTargetExternalDependendedUponTargets = filterDependencies(from: graphDependenciesWithExternalDependencies)
            .compactMap { graphDependency -> GraphTarget? in
                if case let GraphDependency.target(name, path) = graphDependency {
                    guard let target = graph.targets[path]?[name],
                          let project = graph.projects[path]
                    else {
                        return nil
                    }
                    return GraphTarget(path: path, target: target, project: project)
                } else {
                    return nil
                }
            }
        let allExternalTargets = allExternalTargets()
        return allExternalTargets.subtracting(allTargetExternalDependendedUponTargets)
    }

    // swiftlint:disable:next function_body_length
    public func allSwiftPluginExecutables(path: TSCBasic.AbsolutePath, name: String) -> Set<String> {
        func precompiledMacroDependencies(_ graphDependency: GraphDependency) -> Set<AbsolutePath> {
            Set(
                dependencies[graphDependency, default: Set()]
                    .lazy
                    .compactMap {
                        if case let GraphDependency.macro(path) = $0 {
                            return path
                        } else {
                            return nil
                        }
                    }
            )
        }

        let precompiledMacroPluginExecutables = filterDependencies(from: .target(name: name, path: path), test: { dependency in
            switch dependency {
            case .xcframework:
                return !precompiledMacroDependencies(dependency).isEmpty
            case .macro:
                return true
            case .bundle, .library, .framework, .sdk, .target, .packageProduct:
                return false
            }
        }, skip: { dependency in
            switch dependency {
            case .macro:
                return true
            case .bundle, .library, .framework, .sdk, .target, .packageProduct, .xcframework:
                return false
            }
        })
        .flatMap { dependency in
            switch dependency {
            case .xcframework:
                return Array(precompiledMacroDependencies(dependency))
            case let .macro(path):
                return [path]
            case .bundle, .library, .framework, .sdk, .target, .packageProduct:
                return []
            }
        }
        .map { "\($0.pathString)#\($0.basename.replacingOccurrences(of: ".macro", with: ""))" }

        let sourceMacroPluginExecutables = allSwiftMacroTargets(path: path, name: name)
            .flatMap { target in
                directSwiftMacroExecutables(path: target.project.path, name: target.target.name).map { (target, $0) }
            }
            .compactMap { _, dependencyReference in
                switch dependencyReference {
                case let .product(_, productName, _):
                    return "$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME/\(productName)#\(productName)"
                default:
                    return nil
                }
            }

        return Set(precompiledMacroPluginExecutables + sourceMacroPluginExecutables)
    }

    // MARK: - Internal

    /// The method collects the dependencies that are selected by the provided test closure.
    /// The skip closure allows skipping the traversing of a specific dependendency branch.
    /// - Parameters:
    ///   - from: Dependency from which the traverse is done.
    ///   - test: If the closure returns true, the dependency is included.
    ///   - skip: If the closure returns false, the traversing logic doesn't traverse the dependencies from that dependency.
    func filterDependencies(
        from rootDependency: GraphDependency,
        test: (GraphDependency) -> Bool = { _ in true },
        skip: (GraphDependency) -> Bool = { _ in false }
    ) -> Set<GraphDependency> {
        filterDependencies(from: [rootDependency], test: test, skip: skip)
    }

    /// The method collects the dependencies that are selected by the provided test closure.
    /// The skip closure allows skipping the traversing of a specific dependendency branch.
    /// - Parameters:
    ///   - from: Dependencies from which the traverse is done.
    ///   - test: If the closure returns true, the dependency is included.
    ///   - skip: If the closure returns false, the traversing logic doesn't traverse the dependencies from that dependency.
    func filterDependencies(
        from rootDependencies: Set<GraphDependency>,
        test: (GraphDependency) -> Bool = { _ in true },
        skip: (GraphDependency) -> Bool = { _ in false }
    ) -> Set<GraphDependency> {
        var stack = Stack<GraphDependency>()

        stack.push(Array(rootDependencies))

        var visited: Set<GraphDependency> = .init()
        var references = Set<GraphDependency>()

        while !stack.isEmpty {
            guard let node = stack.pop() else {
                continue
            }

            if visited.contains(node) {
                continue
            }

            visited.insert(node)

            if !rootDependencies.contains(node), test(node) {
                references.insert(node)
            }

            if !rootDependencies.contains(node), skip(node) {
                continue
            }

            graph.dependencies[node]?.forEach { nodeDependency in
                if !visited.contains(nodeDependency) {
                    stack.push(nodeDependency)
                }
            }
        }
        return references
    }

    /// Recursively find platform filters within transitive dependencies
    /// - Parameters:
    ///   - rootDependency: dependency whose platform filters we need when depending on `transitiveDependency`
    ///   - transitiveDependency: target dependency
    /// - Returns: CombinationResult which represents a resolved condition or `.incompatible` based on traversing
    public func combinedCondition(
        to transitiveDependency: GraphDependency,
        from rootDependency: GraphDependency
    ) -> PlatformCondition
        .CombinationResult
    {
        if let cached = conditionCache[(rootDependency, transitiveDependency)] {
            return cached
        } else if graph.dependencyConditions.isEmpty {
            return .condition(nil)
        }

        // if we're at a leaf dependency, there is nothing else to traverse.
        guard let dependencies = graph.dependencies[rootDependency] else { return .incompatible }

        let result: PlatformCondition.CombinationResult

        // We've reached our destination, return a condition for the leaf relationship (`nil` or a `PlatformFilters` set)
        if dependencies.contains(transitiveDependency) {
            result = .condition(graph.dependencyConditions[(rootDependency, transitiveDependency)])
        } else {
            // Capture the filters that could be applied to intermediate dependencies
            // A --> (.ios) B --> C : C should have the .ios filter applied due to B
            let filters = dependencies.map { node -> PlatformCondition.CombinationResult in
                let transitive = combinedCondition(to: transitiveDependency, from: node)
                let currentCondition = graph.dependencyConditions[(rootDependency, node)]
                switch transitive {
                case .incompatible:
                    return .incompatible
                case let .condition(.some(condition)):
                    return condition.intersection(currentCondition)
                case .condition:
                    return .condition(currentCondition)
                }
            }

            // Union our filters because multiple paths could lead to the same dependency (e.g. AVFoundation)
            //  A --> (.ios) B --> C
            //  A --> (.macos) D --> C
            // C should have `[.ios, .macos]` set for filters to satisfy both paths
            let transitiveFilters = filters.compactMap { $0 }
                .reduce(PlatformCondition.CombinationResult.incompatible) { result, condition in
                    result.combineWith(condition)
                }

            result = transitiveFilters
        }

        conditionCache[(rootDependency, transitiveDependency)] = result
        return result
    }

    public func externalTargetSupportedPlatforms() -> [GraphTarget: Set<Platform>] {
        let targetsWithExternalDependencies = targetsWithExternalDependencies()
        var platforms: [GraphTarget: Set<Platform>] = [:]

        func traverse(target: GraphTarget, parentPlatforms: Set<Platform>) {
            let dependencies = directTargetDependencies(path: target.path, name: target.target.name)

            for dependencyTargetReference in dependencies {
                var platformsToInsert: Set<Platform>?
                let dependencyTarget = dependencyTargetReference.graphTarget
                let inheritedPlatforms = dependencyTarget.target.product == .macro ? Set<Platform>([.macOS]) : parentPlatforms
                if let dependencyCondition = dependencyTargetReference.condition,
                   let platformIntersection = PlatformCondition.when(target.target.dependencyPlatformFilters)?
                   .intersection(dependencyCondition)
                {
                    switch platformIntersection {
                    case .incompatible:
                        break
                    case let .condition(condition):
                        if let condition {
                            let dependencyPlatforms = Set(
                                condition.platformFilters.map(\.platform)
                                    .filter { $0 != nil }
                                    .map { $0! }
                            )
                            .intersection(inheritedPlatforms)
                            platformsToInsert = dependencyPlatforms
                        }
                    }
                } else {
                    platformsToInsert = inheritedPlatforms.intersection(dependencyTarget.target.supportedPlatforms)
                }

                if let platformsToInsert {
                    var existingPlatforms = platforms[dependencyTarget, default: Set()]
                    let continueTraversing = !platformsToInsert.isSubset(of: existingPlatforms)
                    existingPlatforms.formUnion(platformsToInsert)
                    platforms[dependencyTarget] = existingPlatforms

                    if continueTraversing {
                        traverse(target: dependencyTarget, parentPlatforms: platforms[dependencyTarget, default: Set()])
                    }
                }
            }
        }

        targetsWithExternalDependencies.forEach { traverse(target: $0, parentPlatforms: $0.target.supportedPlatforms) }
        return platforms
    }

    func allDependenciesSatisfy(from rootDependency: GraphDependency, meets: (GraphDependency) -> Bool) -> Bool {
        var allSatisfy = true
        _ = filterDependencies(from: rootDependency, test: { dependency in
            if !meets(dependency) {
                allSatisfy = false
            }
            return true
        })
        return allSatisfy
    }

    func transitiveStaticDependencies(from dependency: GraphDependency) -> Set<GraphDependency> {
        filterDependencies(
            from: dependency,
            test: isDependencyStatic,
            skip: or(canDependencyLinkStaticProducts, isDependencyPrecompiledMacro)
        )
    }

    func isDependencyPrecompiledMacro(_ dependency: GraphDependency) -> Bool {
        switch dependency {
        case .macro:
            return true
        case .bundle, .framework, .xcframework, .library, .sdk, .target, .packageProduct:
            return false
        }
    }

    func isDependencyPrecompiledLibrary(dependency: GraphDependency) -> Bool {
        switch dependency {
        case .macro: return false
        case .xcframework: return true
        case .framework: return true
        case .library: return true
        case .bundle: return true
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        }
    }

    func isDependencyPrecompiledFramework(dependency: GraphDependency) -> Bool {
        switch dependency {
        case .macro: return false
        case .xcframework: return true
        case .framework: return true
        case .library: return false
        case .bundle: return false
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        }
    }

    func isXCFrameworkMerged(dependency: GraphDependency, expectedMergedBinaries: Set<String>) -> Bool {
        guard case let .xcframework(xcframework) = dependency,
              let binaryName = xcframework.infoPlist.libraries.first?.binaryName,
              expectedMergedBinaries.contains(binaryName)
        else {
            return false
        }
        if !xcframework.mergeable {
            fatalError("XCFramework \(binaryName) must be compiled with  -make_mergeable option enabled")
        }
        return xcframework.mergeable
    }

    func isDependencyDynamicNonMergeableTarget(dependency: GraphDependency) -> Bool {
        guard case let GraphDependency.target(name, path) = dependency,
              let target = target(path: path, name: name) else { return false }
        return !target.target.mergeable
    }

    func isDependencyStaticTarget(dependency: GraphDependency) -> Bool {
        guard case let GraphDependency.target(name, path) = dependency,
              let target = target(path: path, name: name) else { return false }
        return target.target.product.isStatic
    }

    func isDependencyStatic(dependency: GraphDependency) -> Bool {
        switch dependency {
        case .macro:
            return false
        case let .xcframework(xcframework):
            return xcframework.linking == .static
        case let .framework(_, _, _, _, linking, _, _),
             let .library(_, _, linking, _, _):
            return linking == .static
        case .bundle: return false
        case .packageProduct: return false
        case let .target(name, path):
            guard let target = target(path: path, name: name) else { return false }
            return target.target.product.isStatic
        case .sdk: return false
        }
    }

    func isDependencyDynamicLibrary(dependency: GraphDependency) -> Bool {
        guard case let GraphDependency.target(name, path) = dependency,
              let target = target(path: path, name: name) else { return false }
        return target.target.product == .dynamicLibrary
    }

    func isDependencyFramework(dependency: GraphDependency) -> Bool {
        guard case let GraphDependency.target(name, path) = dependency,
              let target = target(path: path, name: name) else { return false }
        return target.target.product == .framework
    }

    func isDependencyDynamicTarget(dependency: GraphDependency) -> Bool {
        switch dependency {
        case .macro: return false
        case .xcframework: return false
        case .framework: return false
        case .library: return false
        case .bundle: return false
        case .packageProduct: return false
        case let .target(name, path):
            guard let target = target(path: path, name: name) else { return false }
            return target.target.product.isDynamic
        case .sdk: return false
        }
    }

    func isDependencyPrecompiledDynamicAndLinkable(dependency: GraphDependency) -> Bool {
        switch dependency {
        case let .xcframework(xcframework):
            return xcframework.linking == .dynamic
        case let .framework(_, _, _, _, linking, _, _),
             let .library(path: _, publicHeaders: _, linking: linking, architectures: _, swiftModuleMap: _):
            return linking == .dynamic
        case .bundle: return false
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        case .macro: return false
        }
    }

    func canDependencyEmbedProducts(dependency: GraphDependency) -> Bool {
        guard case let GraphDependency.target(name, path) = dependency,
              let target = target(path: path, name: name) else { return false }
        return canEmbedProducts(target: target.target)
    }

    func canDependencyLinkStaticProducts(dependency: GraphDependency) -> Bool {
        guard case let GraphDependency.target(name, path) = dependency,
              let target = target(path: path, name: name) else { return false }
        return target.target.canLinkStaticProducts()
    }

    func unitTestHost(path: AbsolutePath, name: String) -> GraphTarget? {
        directLocalTargetDependencies(path: path, name: name)
            .first(where: { $0.target.product.canHostTests() })?.graphTarget
    }

    func canEmbedProducts(target: Target) -> Bool {
        let validProducts: [Product] = [
            .app,
            .appClip,
            .unitTests,
            .uiTests,
            .watch2Extension,
            .systemExtension,
            .xpc,
        ]
        return validProducts.contains(target.product)
    }

    // swiftlint:disable:next function_body_length
    func dependencyReference(
        to toDependency: GraphDependency,
        from fromDependency: GraphDependency
    ) -> GraphDependencyReference? {
        guard case let .condition(condition) = combinedCondition(to: toDependency, from: fromDependency) else {
            return nil
        }

        switch toDependency {
        case let .macro(path):
            return .macro(path: path)
        case let .framework(path, binaryPath, dsymPath, bcsymbolmapPaths, linking, architectures, status):
            return .framework(
                path: path,
                binaryPath: binaryPath,
                dsymPath: dsymPath,
                bcsymbolmapPaths: bcsymbolmapPaths,
                linking: linking,
                architectures: architectures,
                product: (linking == .static) ? .staticFramework : .framework,
                status: status,
                condition: condition
            )
        case let .library(path, _, linking, architectures, _):
            return .library(
                path: path,
                linking: linking,
                architectures: architectures,
                product: (linking == .static) ? .staticLibrary : .dynamicLibrary,
                condition: condition
            )
        case let .bundle(path):
            return .bundle(path: path, condition: condition)
        case .packageProduct:
            return nil
        case let .sdk(_, path, status, source):
            return .sdk(
                path: path,
                status: status,
                source: source,
                condition: condition
            )
        case let .target(name, path):
            guard let target = target(path: path, name: name) else { return nil }
            return .product(
                target: target.target.name,
                productName: target.target.productNameWithExtension,
                condition: condition
            )
        case let .xcframework(xcframework):
            return .xcframework(
                path: xcframework.path,
                infoPlist: xcframework.infoPlist,
                primaryBinaryPath: xcframework.primaryBinaryPath,
                binaryPath: xcframework.primaryBinaryPath,
                status: xcframework.status,
                condition: condition
            )
        }
    }

    private func isDependencyResourceBundle(dependency: GraphDependency) -> Bool {
        switch dependency {
        case .bundle:
            return true
        case let .target(name: name, path: path):
            return target(path: path, name: name)?.target.product == .bundle
        default:
            return false
        }
    }

    private func allTargets(excludingExternalTargets: Bool) -> Set<GraphTarget> {
        Set(projects.flatMap { projectPath, project -> [GraphTarget] in
            if excludingExternalTargets, project.isExternal { return [] }

            let targets = graph.targets[projectPath, default: [:]]
            return targets.values.map { target in
                GraphTarget(path: projectPath, target: target, project: project)
            }
        })
    }

    private func staticPrecompiledFrameworksDependencies(
        path: AbsolutePath,
        name: String
    ) -> [GraphDependencyReference] {
        let precompiledStatic = graph.dependencies[.target(name: name, path: path), default: []]
            .filter { dependency in
                switch dependency {
                case let .framework(_, _, _, _, linking: linking, _, _):
                    return linking == .static
                case .xcframework, .library, .bundle, .packageProduct, .target, .sdk, .macro:
                    return false
                }
            }

        let precompiledDependencies = precompiledStatic
            .flatMap { filterDependencies(from: $0) }

        return Set(precompiledStatic + precompiledDependencies)
            .compactMap { dependencyReference(to: $0, from: .target(name: name, path: path)) }
    }

    private func staticPrecompiledXCFrameworksDependencies(
        path: AbsolutePath,
        name: String
    ) -> [GraphDependencyReference] {
        let dependencies = filterDependencies(
            from: .target(name: name, path: path),
            test: { dependency in
                switch dependency {
                case let .xcframework(xcframework):
                    return xcframework.linking == .static
                case .framework, .library, .bundle, .packageProduct, .target, .sdk, .macro:
                    return false
                }
            },
            skip: { $0.isDynamicPrecompiled || !$0.isPrecompiled || $0.isPrecompiledMacro }
        )
        return Set(dependencies)
            .compactMap { dependencyReference(to: $0, from: .target(name: name, path: path)) }
    }
}

// swiftlint:enable type_body_length
