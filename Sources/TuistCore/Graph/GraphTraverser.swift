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
                Array(directTargetDependencies(path: $0.path, name: $0.target.name))
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
            guard case let GraphDependency.framework(path, _, _, _, _, _, _, _) = dependency else { return nil }
            return path
        })
    }

    public func targets(product: Product) -> Set<GraphTarget> {
        var filteredTargets: Set<GraphTarget> = Set()
        targets.forEach { path, projectTargets in
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

    public func directTargetDependencies(path: AbsolutePath, name: String) -> Set<GraphTarget> {
        guard let dependencies = graph.dependencies[.target(name: name, path: path)]
        else { return [] }

        let targetDependencies = dependencies
            .compactMap(\.targetDependency)

        return Set(targetDependencies.flatMap { dependencyName, dependencyPath -> [GraphTarget] in
            guard let projectDependencies = graph.targets[dependencyPath],
                  let dependencyTarget = projectDependencies[dependencyName],
                  let dependencyProject = graph.projects[dependencyPath]
            else {
                return []
            }
            return [GraphTarget(path: dependencyPath, target: dependencyTarget, project: dependencyProject)]
        })
    }

    public func directLocalTargetDependencies(path: AbsolutePath, name: String) -> Set<GraphTarget> {
        guard let dependencies = graph.dependencies[.target(name: name, path: path)] else { return [] }
        guard let project = graph.projects[path] else { return Set() }

        let localTargetDependencies = dependencies
            .compactMap(\.targetDependency)
            .filter { $0.path == path }
        return Set(localTargetDependencies.flatMap { dependencyName, dependencyPath -> [GraphTarget] in
            guard let projectDependencies = graph.targets[dependencyPath],
                  let dependencyTarget = projectDependencies[dependencyName]
            else {
                return []
            }
            return [GraphTarget(path: path, target: dependencyTarget, project: project)]
        })
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

    public func appExtensionDependencies(path: AbsolutePath, name: String) -> Set<GraphTarget> {
        let validProducts: [Product] = [
            .appExtension, .stickerPackExtension, .watch2Extension, .tvTopShelfExtension, .messagesExtension,
        ]
        return Set(
            directLocalTargetDependencies(path: path, name: name)
                .filter { validProducts.contains($0.target.product) }
        )
    }

    public func extensionKitExtensionDependencies(path: TSCBasic.AbsolutePath, name: String) -> Set<TuistGraph.GraphTarget> {
        let validProducts: [Product] = [
            .extensionKitExtension,
        ]
        return Set(
            directLocalTargetDependencies(path: path, name: name)
                .filter { validProducts.contains($0.target.product) }
        )
    }

    public func appClipDependencies(path: AbsolutePath, name: String) -> GraphTarget? {
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
            test: isDependencyPrecompiledDynamicAndLinkable,
            skip: canDependencyEmbedProducts
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
                platformFilters: [.ios]
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
            .flatMap { filterDependencies(from: $0) }

        let precompiledLibrariesAndFrameworks = Set(precompiled + precompiledDependencies)
            .filter(isDependencyPrecompiledDynamicAndLinkable)
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
                    .filter(\.isPrecompiled)
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
                platformFilters: [.macos]
            ) }

        return Set(dependencies)
    }

    public func directSwiftMacroFrameworkTargets(path: AbsolutePath, name: String) -> Set<GraphTarget> {
        let dependencies = directTargetDependencies(path: path, name: name)
            .filter { $0.target.product == .staticFramework }
            .filter { self.directSwiftMacroExecutables(path: $0.path, name: $0.target.name).count != 0 }
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
            case let .library(path: path, linking: _, architectures: _, product: _, platformFilters: _):
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
            test: isDependencyPrecompiledDynamicAndLinkable,
            skip: canDependencyEmbedProducts
        )
        .lazy
        .compactMap { (dependency: GraphDependency) -> AbsolutePath? in
            switch dependency {
            case let .xcframework(path, _, _, _, _, _): return path
            case let .framework(path, _, _, _, _, _, _, _): return path
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
        try targets.forEach { target in
            try references.formUnion(self.linkableDependencies(path: path, name: target.target.name))
            references.formUnion(self.embeddableFrameworks(path: path, name: target.target.name))
            references.formUnion(self.copyProductDependencies(path: path, name: target.target.name))
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
        var stack = Stack<GraphDependency>()

        stack.push(rootDependency)

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

            if node != rootDependency, test(node) {
                references.insert(node)
            }

            if node != rootDependency, skip(node) {
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
    /// - Returns: PlatformFilters to apply to transitive dependency or `nil` if there isnt a path or path to a dependency results
    /// in a disjoint
    /// set of platform filters
    func platformFilters(to transitiveDependency: GraphDependency, from rootDependency: GraphDependency) -> PlatformFilters {
        var visited: Set<GraphDependency> = []

        func find(from root: GraphDependency, to other: GraphDependency) -> PlatformFilters {
            // Skip already visited nodes
            guard !visited.contains(root) else { return .invalid }
            visited.insert(root)

            // if we're at a leaf dependency, there is nothing else to traverse.
            guard let dependencies = graph.dependencies[root] else { return .invalid }

            // We've reached our destination, return the filters or `.all` if none are set
            if dependencies.contains(other) {
                return graph.dependencyPlatformFilters[(root, other)]
            } else {
                // We have more dependencies to traverse.
                // Form the union of all set filters that reach our target.
                let filters = dependencies.map { node -> PlatformFilters in
                    let transitive = find(from: node, to: other)

                    // Capture the filters that could be applied to intermediate dependencies
                    // A --> (.ios) B --> C : C should have the .ios filter applied due to B
                    let currentDependencyPlatformFilters = graph.dependencyPlatformFilters[(root, node)]
                    return transitive.intersection(currentDependencyPlatformFilters)
                }

                // Union our filters because multiple paths could lead to the same dependency (e.g. AVFoundation)
                //  A --> (.ios) B --> C
                //  A --> (.macos) D --> C
                // C should have `[.ios, .macos]` set for filters to satisfy both paths
                let transitiveFilters = filters.compactMap { $0 }.reduce(Set<PlatformFilter>()) { result, otherFilters in
                    result.union(otherFilters)
                }

                return transitiveFilters
            }
        }

        return find(from: rootDependency, to: transitiveDependency)
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
            skip: canDependencyLinkStaticProducts
        )
    }

    func targetProductReference(target: GraphTarget) -> GraphDependencyReference {
        .product(
            target: target.target.name,
            productName: target.target.productNameWithExtension,
            platformFilters: target.target.dependencyPlatformFilters
        )
    }

    func isDependencyPrecompiledLibrary(dependency: GraphDependency) -> Bool {
        switch dependency {
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
        guard case let .xcframework(_, infoPlist, _, _, mergeable, _) = dependency,
              let binaryName = infoPlist.libraries.first?.binaryName,
              expectedMergedBinaries.contains(binaryName)
        else {
            return false
        }
        if !mergeable {
            fatalError("XCFramework \(binaryName) must be compiled with  -make_mergeable option enabled")
        }
        return mergeable
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
        case let .xcframework(_, _, _, linking, _, _),
             let .framework(_, _, _, _, linking, _, _, _),
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
        case let .xcframework(_, _, _, linking, _, _),
             let .framework(_, _, _, _, linking, _, _, _),
             let .library(path: _, publicHeaders: _, linking: linking, architectures: _, swiftModuleMap: _):
            return linking == .dynamic
        case .bundle: return false
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
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
            .first(where: { $0.target.product.canHostTests() })
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

    func dependencyReference(
        to toDependency: GraphDependency,
        from fromDependency: GraphDependency
    ) -> GraphDependencyReference? {
        let platformFilters = platformFilters(to: toDependency, from: fromDependency)
        guard platformFilters != .invalid else {
            return nil
        }

        switch toDependency {
        case let .framework(path, binaryPath, dsymPath, bcsymbolmapPaths, linking, architectures, isCarthage, status):
            return .framework(
                path: path,
                binaryPath: binaryPath,
                isCarthage: isCarthage,
                dsymPath: dsymPath,
                bcsymbolmapPaths: bcsymbolmapPaths,
                linking: linking,
                architectures: architectures,
                product: (linking == .static) ? .staticFramework : .framework,
                status: status,
                platformFilters: platformFilters
            )
        case let .library(path, _, linking, architectures, _):
            return .library(
                path: path,
                linking: linking,
                architectures: architectures,
                product: (linking == .static) ? .staticLibrary : .dynamicLibrary,
                platformFilters: platformFilters
            )
        case let .bundle(path):
            return .bundle(path: path, platformFilters: platformFilters)
        case .packageProduct:
            return nil
        case let .sdk(_, path, status, source):
            return .sdk(
                path: path,
                status: status,
                source: source,
                platformFilters: platformFilters
            )
        case let .target(name, path):
            guard let target = target(path: path, name: name) else { return nil }
            return .product(
                target: target.target.name,
                productName: target.target.productNameWithExtension,
                platformFilters: target.target.dependencyPlatformFilters // This will be platformFilters when we
            )
        case let .xcframework(path, infoPlist, primaryBinaryPath, _, _, status):
            return .xcframework(
                path: path,
                infoPlist: infoPlist,
                primaryBinaryPath: primaryBinaryPath,
                binaryPath: primaryBinaryPath,
                status: status,
                platformFilters: platformFilters
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
                case let .framework(_, _, _, _, linking: linking, _, _, _):
                    return linking == .static
                case .xcframework, .library, .bundle, .packageProduct, .target, .sdk:
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
                case let .xcframework(_, _, _, linking: linking, _, _):
                    return linking == .static
                case .framework, .library, .bundle, .packageProduct, .target, .sdk:
                    return false
                }
            },
            skip: { $0.isDynamicPrecompiled || !$0.isPrecompiled }
        )
        return Set(dependencies)
            .compactMap { dependencyReference(to: $0, from: .target(name: name, path: path)) }
    }
}

// swiftlint:enable type_body_length
