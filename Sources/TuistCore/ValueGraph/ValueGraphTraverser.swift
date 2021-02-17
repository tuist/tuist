import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

// swiftlint:disable type_body_length
public class ValueGraphTraverser: GraphTraversing {
    public var name: String { graph.name }
    public var hasPackages: Bool { !graph.packages.flatMap(\.value).isEmpty }
    public var path: AbsolutePath { graph.path }
    public var workspace: Workspace { graph.workspace }
    public var projects: [AbsolutePath: Project] { graph.projects }
    public var targets: [AbsolutePath: [String: Target]] { graph.targets }
    public var dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] { graph.dependencies }

    private let graph: ValueGraph

    public required init(graph: ValueGraph) {
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

    public func rootTargets() -> Set<ValueGraphTarget> {
        Set(graph.workspace.projects.reduce(into: Set()) { result, path in
            result.formUnion(targets(at: path))
        })
    }

    public func allTargets() -> Set<ValueGraphTarget> {
        Set(projects.flatMap { (projectPath, project) -> [ValueGraphTarget] in
            let targets = graph.targets[projectPath, default: [:]]
            return targets.values.map { target in
                ValueGraphTarget(path: projectPath, target: target, project: project)
            }
        })
    }

    public func rootProjects() -> Set<Project> {
        Set(graph.workspace.projects.compactMap {
            projects[$0]
        })
    }

    public func schemes() -> [Scheme] {
        projects.values.flatMap(\.schemes) + graph.workspace.schemes
    }

    public func cocoapodsPaths() -> Set<AbsolutePath> {
        dependencies.reduce(into: Set<AbsolutePath>()) { acc, next in
            let fromDependency = next.key
            let toDependencies = next.value
            if case let ValueGraphDependency.cocoapods(path) = fromDependency {
                acc.insert(path)
            }
            toDependencies.forEach { toDependency in
                if case let ValueGraphDependency.cocoapods(path) = toDependency {
                    acc.insert(path)
                }
            }
        }
    }

    public func precompiledFrameworksPaths() -> Set<AbsolutePath> {
        let dependencies = graph.dependencies.reduce(into: Set<ValueGraphDependency>()) { acc, next in
            acc.formUnion([next.key])
            acc.formUnion(next.value)
        }
        return Set(dependencies.compactMap { dependency -> AbsolutePath? in
            guard case let ValueGraphDependency.framework(path, _, _, _, _, _, _) = dependency else { return nil }
            return path
        })
    }

    public func targets(product: Product) -> Set<ValueGraphTarget> {
        var filteredTargets: Set<ValueGraphTarget> = Set()
        targets.forEach { path, projectTargets in
            projectTargets.values.forEach { target in
                guard target.product == product else { return }
                guard let project = projects[path] else { return }
                filteredTargets.formUnion([ValueGraphTarget(path: path, target: target, project: project)])
            }
        }
        return filteredTargets
    }

    public func target(path: AbsolutePath, name: String) -> ValueGraphTarget? {
        guard let project = graph.projects[path], let target = graph.targets[path]?[name] else { return nil }
        return ValueGraphTarget(path: path, target: target, project: project)
    }

    public func targets(at path: AbsolutePath) -> Set<ValueGraphTarget> {
        guard let project = graph.projects[path] else { return Set() }
        guard let targets = graph.targets[path] else { return [] }
        return Set(targets.values.map { ValueGraphTarget(path: path, target: $0, project: project) })
    }

    public func directTargetDependencies(path: AbsolutePath, name: String) -> Set<ValueGraphTarget> {
        guard let dependencies = graph.dependencies[.target(name: name, path: path)] else { return [] }
        guard let project = graph.projects[path] else { return Set() }

        let localTargetDependencies = dependencies
            .compactMap(\.targetDependency)
            .filter { $0.path == path }
        return Set(localTargetDependencies.flatMap { (dependencyName, dependencyPath) -> [ValueGraphTarget] in
            guard let projectDependencies = graph.targets[dependencyPath],
                let dependencyTarget = projectDependencies[dependencyName]
            else {
                return []
            }
            return [ValueGraphTarget(path: path, target: dependencyTarget, project: project)]
        })
    }

    public func resourceBundleDependencies(path: AbsolutePath, name: String) -> Set<ValueGraphTarget> {
        guard let target = graph.targets[path]?[name] else { return [] }
        guard target.supportsResources else { return [] }

        let canHostResources: (ValueGraphDependency) -> Bool = {
            self.target(from: $0)?.target.supportsResources == true
        }

        let isBundle: (ValueGraphDependency) -> Bool = {
            self.target(from: $0)?.target.product == .bundle
        }

        let bundles = filterDependencies(from: .target(name: name, path: path),
                                         test: isBundle,
                                         skip: canHostResources)
        let bundleTargets = bundles.compactMap(target(from:))

        return Set(bundleTargets)
    }

    public func testTargetsDependingOn(path: AbsolutePath, name: String) -> Set<ValueGraphTarget> {
        guard let project = graph.projects[path] else { return Set() }

        return Set(graph.targets[path]?.values
            .filter { $0.product.testsBundle }
            .filter { graph.dependencies[.target(name: $0.name, path: path)]?.contains(.target(name: name, path: path)) == true }
            .map { ValueGraphTarget(path: path, target: $0, project: project) } ?? [])
    }

    public func target(from dependency: ValueGraphDependency) -> ValueGraphTarget? {
        guard case let ValueGraphDependency.target(name, path) = dependency else {
            return nil
        }
        guard let target = graph.targets[path]?[name] else { return nil }
        guard let project = graph.projects[path] else { return nil }
        return ValueGraphTarget(path: path, target: target, project: project)
    }

    public func appExtensionDependencies(path: AbsolutePath, name: String) -> Set<ValueGraphTarget> {
        let validProducts: [Product] = [
            .appExtension, .stickerPackExtension, .watch2Extension, .messagesExtension,
        ]
        return Set(directTargetDependencies(path: path, name: name)
            .filter { validProducts.contains($0.target.product) })
    }

    public func appClipDependencies(path: AbsolutePath, name: String) -> ValueGraphTarget? {
        directTargetDependencies(path: path, name: name)
            .first { $0.target.product == .appClip }
    }

    public func directStaticDependencies(path: AbsolutePath, name: String) -> Set<GraphDependencyReference> {
        Set(graph.dependencies[.target(name: name, path: path)]?
            .compactMap { (dependency: ValueGraphDependency) -> (path: AbsolutePath, name: String)? in
                guard case let ValueGraphDependency.target(name, path) = dependency else {
                    return nil
                }
                return (path, name)
            }
            .compactMap { graph.targets[$0.path]?[$0.name] }
            .filter { $0.product.isStatic }
            .map { .product(target: $0.name, productName: $0.productNameWithExtension) } ?? [])
    }

    public func embeddableFrameworks(path: AbsolutePath, name: String) -> Set<GraphDependencyReference> {
        guard let target = self.target(path: path, name: name), canEmbedProducts(target: target.target) else { return Set() }

        var references: Set<GraphDependencyReference> = Set([])

        /// Precompiled frameworks
        let precompiledFrameworks = filterDependencies(from: .target(name: name, path: path),
                                                       test: isDependencyPrecompiledDynamicAndLinkable,
                                                       skip: canDependencyEmbedProducts)
            .lazy
            .compactMap(dependencyReference)
        references.formUnion(precompiledFrameworks)

        /// Other targets' frameworks.
        let otherTargetFrameworks = filterDependencies(from: .target(name: name, path: path),
                                                       test: isDependencyDynamicTarget,
                                                       skip: canDependencyEmbedProducts)
            .lazy
            .compactMap(dependencyReference)
        references.formUnion(otherTargetFrameworks)

        // Exclude any products embed in unit test host apps
        if target.target.product == .unitTests {
            if let hostApp = hostApplication(path: path, name: name) {
                references.subtract(embeddableFrameworks(path: hostApp.path, name: hostApp.target.name))
            } else {
                references = Set()
            }
        }

        return references
    }

    public func linkableDependencies(path: AbsolutePath, name: String) throws -> Set<GraphDependencyReference> {
        guard let target = self.target(path: path, name: name) else { return Set() }

        var references = Set<GraphDependencyReference>()

        // System libraries and frameworks
        if target.target.canLinkStaticProducts() {
            let transitiveSystemLibraries = transitiveStaticTargets(from: .target(name: name, path: path))
                .flatMap { (dependency) -> [GraphDependencyReference] in
                    let dependencies = self.graph.dependencies[dependency, default: []]
                    return dependencies.compactMap { dependencyDependency -> GraphDependencyReference? in
                        guard case let ValueGraphDependency.sdk(_, path, status, source) = dependencyDependency else { return nil }
                        return .sdk(path: path, status: status, source: source)
                    }
                }
            references.formUnion(transitiveSystemLibraries)
        }

        // AppClip dependencies
        if target.target.isAppClip {
            let path = try SDKNode.appClip(status: .required).path
            references.formUnion([GraphDependencyReference.sdk(path: path,
                                                               status: .required,
                                                               source: .system)])
        }

        // Direct system libraries and frameworks
        let directSystemLibrariesAndFrameworks = graph.dependencies[.target(name: name, path: path), default: []]
            .compactMap { dependency -> GraphDependencyReference? in
                guard case let ValueGraphDependency.sdk(_, path, status, source) = dependency else { return nil }
                return .sdk(path: path, status: status, source: source)
            }
        references.formUnion(directSystemLibrariesAndFrameworks)

        // Precompiled libraries and frameworks
        let precompiled = graph.dependencies[.target(name: name, path: path), default: []]
            .lazy
            .filter(\.isPrecompiled)

        let precompiledDependencies = precompiled
            .flatMap { filterDependencies(from: $0) }

        let precompiledLibrariesAndFrameworks = Set(precompiled + precompiledDependencies)
            .compactMap(dependencyReference)

        references.formUnion(precompiledLibrariesAndFrameworks)

        // Static libraries and frameworks / Static libraries' dynamic libraries
        if target.target.canLinkStaticProducts() {
            var transitiveStaticTargets = self.transitiveStaticTargets(from: .target(name: name, path: path))

            // Exclude any static products linked in a host application
            if target.target.product == .unitTests {
                if let hostApp = hostApplication(path: path, name: name) {
                    transitiveStaticTargets.subtract(self.transitiveStaticTargets(from: .target(name: hostApp.target.name, path: hostApp.project.path)))
                }
            }

            let transitiveStaticTargetReferences = transitiveStaticTargets.compactMap(dependencyReference)

            let staticDependenciesDynamicLibrariesAndFrameworks = transitiveStaticTargets.flatMap { (dependency) -> [GraphDependencyReference] in
                self.graph.dependencies[dependency, default: []]
                    .lazy
                    .filter(\.isTarget)
                    .filter(isDependencyDynamicTarget)
                    .compactMap(dependencyReference)
            }

            let staticDependenciesPrecompiledDynamicLibrariesAndFrameworks = transitiveStaticTargets.flatMap { (dependency) -> [GraphDependencyReference] in
                self.graph.dependencies[dependency, default: []]
                    .lazy
                    .filter(\.isPrecompiled)
                    .filter(isDependencyPrecompiledDynamicAndLinkable)
                    .compactMap(dependencyReference)
            }

            references.formUnion(
                transitiveStaticTargetReferences
                    + staticDependenciesDynamicLibrariesAndFrameworks
                    + staticDependenciesPrecompiledDynamicLibrariesAndFrameworks
            )
        }

        // Link dynamic libraries and frameworks
        let dynamicLibrariesAndFrameworks = graph.dependencies[.target(name: name, path: path), default: []]
            .filter(or(isDependencyDynamicLibrary, isDependencyFramework))
            .compactMap(dependencyReference)
        references.formUnion(dynamicLibrariesAndFrameworks)

        return references
    }

    public func copyProductDependencies(path: AbsolutePath, name: String) -> Set<GraphDependencyReference> {
        guard let target = self.target(path: path, name: name) else { return Set() }

        var dependencies = Set<GraphDependencyReference>()

        if target.target.product.isStatic {
            dependencies.formUnion(directStaticDependencies(path: path, name: name))
        }

        dependencies.formUnion(resourceBundleDependencies(path: path, name: name).map(targetProductReference))

        return Set(dependencies)
    }

    public func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        let dependencies = graph.dependencies[.target(name: name, path: path), default: []]
        let libraryPublicHeaders = dependencies.compactMap { dependency -> AbsolutePath? in
            guard case let ValueGraphDependency.library(_, publicHeaders, _, _, _) = dependency else { return nil }
            return publicHeaders
        }
        return Set(libraryPublicHeaders)
    }

    public func librariesSearchPaths(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        let dependencies = graph.dependencies[.target(name: name, path: path), default: []]
        let libraryPaths = dependencies.compactMap { dependency -> AbsolutePath? in
            guard case let ValueGraphDependency.library(path, _, _, _, _) = dependency else { return nil }
            return path
        }
        return Set(libraryPaths.compactMap { $0.removingLastComponent() })
    }

    public func librariesSwiftIncludePaths(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        let dependencies = graph.dependencies[.target(name: name, path: path), default: []]
        let librarySwiftModuleMapPaths = dependencies.compactMap { dependency -> AbsolutePath? in
            guard case let ValueGraphDependency.library(_, _, _, _, swiftModuleMapPath) = dependency else { return nil }
            return swiftModuleMapPath
        }
        return Set(librarySwiftModuleMapPaths.compactMap { $0.removingLastComponent() })
    }

    public func runPathSearchPaths(path: AbsolutePath, name: String) -> Set<AbsolutePath> {
        guard let target = target(path: path, name: name),
            canEmbedProducts(target: target.target),
            target.target.product == .unitTests,
            hostApplication(path: path, name: name) == nil
        else {
            return Set()
        }

        var references: Set<AbsolutePath> = Set([])

        let from = ValueGraphDependency.target(name: name, path: path)
        let precompiledFramewoksPaths = filterDependencies(from: from,
                                                           test: isDependencyPrecompiledDynamicAndLinkable,
                                                           skip: canDependencyEmbedProducts)
            .lazy
            .compactMap { (dependency: ValueGraphDependency) -> AbsolutePath? in
                switch dependency {
                case let .xcframework(path, _, _, _): return path
                case let .framework(path, _, _, _, _, _, _): return path
                case .library: return nil
                case .packageProduct: return nil
                case .target: return nil
                case .sdk: return nil
                case .cocoapods: return nil
                }
            }
            .map(\.parentDirectory)

        references.formUnion(precompiledFramewoksPaths)
        return references
    }

    public func hostTargetFor(path: AbsolutePath, name: String) -> ValueGraphTarget? {
        guard let targets = graph.targets[path] else { return nil }
        guard let project = graph.projects[path] else { return nil }

        return targets.values.compactMap { (target) -> ValueGraphTarget? in
            let dependencies = self.graph.dependencies[.target(name: target.name, path: path), default: Set()]
            let dependsOnTarget = dependencies.contains(where: { dependency in
                // swiftlint:disable:next identifier_name
                guard case let ValueGraphDependency.target(_name, _path) = dependency else { return false }
                return _name == name && _path == path
            })
            let valueGraphTarget = ValueGraphTarget(path: path, target: target, project: project)
            return dependsOnTarget ? valueGraphTarget : nil
        }.first
    }

    public func allProjectDependencies(path: AbsolutePath) throws -> Set<GraphDependencyReference> {
        let targets = self.targets(at: path)
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
        directTargetDependencies(path: path, name: name)
            .first(where: { $0.target.name == "XCTest" || $0.target.product.testsBundle }) != nil
    }

    // MARK: - Internal

    /// The method collects the dependencies that are selected by the provided test closure.
    /// The skip closure allows skipping the traversing of a specific dependendency branch.
    /// - Parameters:
    ///   - from: Dependency from which the traverse is done.
    ///   - test: If the closure returns true, the dependency is included.
    ///   - skip: If the closure returns false, the traversing logic doesn't traverse the dependencies from that dependency.
    func filterDependencies(from rootDependency: ValueGraphDependency,
                            test: (ValueGraphDependency) -> Bool = { _ in true },
                            skip: (ValueGraphDependency) -> Bool = { _ in false }) -> Set<ValueGraphDependency>
    {
        var stack = Stack<ValueGraphDependency>()

        stack.push(rootDependency)

        var visited: Set<ValueGraphDependency> = .init()
        var references = Set<ValueGraphDependency>()

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

    func transitiveStaticTargets(from dependency: ValueGraphDependency) -> Set<ValueGraphDependency> {
        filterDependencies(from: dependency,
                           test: isDependencyStaticTarget,
                           skip: canDependencyLinkStaticProducts)
    }

    func targetProductReference(target: ValueGraphTarget) -> GraphDependencyReference {
        .product(target: target.target.name, productName: target.target.productNameWithExtension)
    }

    func isDependencyPrecompiledLibrary(dependency: ValueGraphDependency) -> Bool {
        switch dependency {
        case .xcframework: return true
        case .framework: return true
        case .library: return true
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        case .cocoapods: return false
        }
    }

    func isDependencyPrecompiledFramework(dependency: ValueGraphDependency) -> Bool {
        switch dependency {
        case .xcframework: return true
        case .framework: return true
        case .library: return false
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        case .cocoapods: return false
        }
    }

    func isDependencyStaticTarget(dependency: ValueGraphDependency) -> Bool {
        guard case let ValueGraphDependency.target(name, path) = dependency,
            let target = self.target(path: path, name: name) else { return false }
        return target.target.product.isStatic
    }

    func isDependencyDynamicLibrary(dependency: ValueGraphDependency) -> Bool {
        guard case let ValueGraphDependency.target(name, path) = dependency,
            let target = self.target(path: path, name: name) else { return false }
        return target.target.product == .dynamicLibrary
    }

    func isDependencyFramework(dependency: ValueGraphDependency) -> Bool {
        guard case let ValueGraphDependency.target(name, path) = dependency,
            let target = self.target(path: path, name: name) else { return false }
        return target.target.product == .framework
    }

    func isDependencyDynamicTarget(dependency: ValueGraphDependency) -> Bool {
        switch dependency {
        case .xcframework: return false
        case .framework: return false
        case .library: return false
        case .packageProduct: return false
        case let .target(name, path):
            guard let target = self.target(path: path, name: name) else { return false }
            return target.target.product.isDynamic
        case .sdk: return false
        case .cocoapods: return false
        }
    }

    func isDependencyPrecompiledDynamicAndLinkable(dependency: ValueGraphDependency) -> Bool {
        switch dependency {
        case let .xcframework(_, _, _, linking): return linking == .dynamic
        case let .framework(_, _, _, _, linking, _, _): return linking == .dynamic
        case .library: return false
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        case .cocoapods: return false
        }
    }

    func canDependencyEmbedProducts(dependency: ValueGraphDependency) -> Bool {
        guard case let ValueGraphDependency.target(name, path) = dependency,
            let target = self.target(path: path, name: name) else { return false }
        return canEmbedProducts(target: target.target)
    }

    func canDependencyLinkStaticProducts(dependency: ValueGraphDependency) -> Bool {
        guard case let ValueGraphDependency.target(name, path) = dependency,
            let target = self.target(path: path, name: name) else { return false }
        return target.target.canLinkStaticProducts()
    }

    func hostApplication(path: AbsolutePath, name: String) -> ValueGraphTarget? {
        directTargetDependencies(path: path, name: name)
            .first(where: { $0.target.product == .app })
    }

    func canEmbedProducts(target: Target) -> Bool {
        let validProducts: [Product] = [
            .app,
            .unitTests,
            .uiTests,
            .watch2Extension,
        ]
        return validProducts.contains(target.product)
    }

    func dependencyReference(dependency: ValueGraphDependency) -> GraphDependencyReference? {
        switch dependency {
        case .cocoapods:
            return nil
        case let .framework(path, binaryPath, dsymPath, bcsymbolmapPaths, linking, architectures, isCarthage):
            return .framework(path: path,
                              binaryPath: binaryPath,
                              isCarthage: isCarthage,
                              dsymPath: dsymPath,
                              bcsymbolmapPaths: bcsymbolmapPaths,
                              linking: linking,
                              architectures: architectures,
                              product: (linking == .static) ? .staticFramework : .framework)
        case let .library(path, _, linking, architectures, _):
            return .library(path: path,
                            linking: linking,
                            architectures: architectures,
                            product: (linking == .static) ? .staticLibrary : .dynamicLibrary)
        case .packageProduct:
            return nil
        case let .sdk(_, path, status, source):
            return .sdk(path: path,
                        status: status,
                        source: source)
        case let .target(name, path):
            guard let target = self.target(path: path, name: name) else { return nil }
            return .product(target: target.target.name, productName: target.target.productNameWithExtension)
        case let .xcframework(path, infoPlist, primaryBinaryPath, _):
            return .xcframework(path: path,
                                infoPlist: infoPlist,
                                primaryBinaryPath: primaryBinaryPath,
                                binaryPath: primaryBinaryPath)
        }
    }
}

// swiftlint:enable type_body_length
