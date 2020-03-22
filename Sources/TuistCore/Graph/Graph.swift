import Basic
import Foundation
import TuistSupport

enum GraphError: FatalError {
    case unsupportedFileExtension(String)

    var description: String {
        switch self {
        case let .unsupportedFileExtension(productType):
            return "Could't obtain product file extension for product type: \(productType)"
        }
    }

    var type: ErrorType {
        switch self {
        case .unsupportedFileExtension:
            return .bug
        }
    }
}

public protocol Graphing: AnyObject, Encodable {
    var name: String { get }
    var entryPath: AbsolutePath { get }
    var entryNodes: [GraphNode] { get }
    var projects: [Project] { get }

    /// Returns all the CocoaPods nodes that are part of the graph.
    var cocoapods: [CocoaPodsNode] { get }

    /// Returns all the SwiftPM package nodes that are part of the graph.
    var packages: [PackageNode] { get }

    /// Returns all the frameorks that are part of the graph.
    var frameworks: [FrameworkNode] { get }

    /// Returns all the precompiled nodes that are part of the graph.
    var precompiled: [PrecompiledNode] { get }

    /// Returns all the targets that are part of the graph.
    var targets: [TargetNode] { get }

    /// Returns all target nodes at a given path (i.e. all target nodes in a project)
    /// - Parameters:
    ///   - path: Path to the directory where the project is located
    func targets(at path: AbsolutePath) -> [TargetNode]

    /// Returns the target with the given name and at the given directory.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func target(path: AbsolutePath, name: String) throws -> TargetNode?

    /// Returns all the non-transitive target dependencies for the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func targetDependencies(path: AbsolutePath, name: String) -> [TargetNode]

    /// Returns all test targets directly dependent on the given target
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func testTargetsDependingOn(path: AbsolutePath, name: String) -> [TargetNode]

    /// Returns all non-transitive target static dependencies for the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func staticDependencies(path: AbsolutePath, name: String) -> [GraphDependencyReference]

    /// Returns the resource bundle dependencies for the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func resourceBundleDependencies(path: AbsolutePath, name: String) -> [TargetNode]

    /// Returns all package dependencies for the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func packages(path: AbsolutePath, name: String) throws -> [PackageNode]

    /// It returns the libraries a given target should be linked against.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func linkableDependencies(path: AbsolutePath, name: String) throws -> [GraphDependencyReference]

    /// Returns the paths for the given target to be able to import the headers from its library dependencies.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> [AbsolutePath]

    /// Returns the search paths for the given target to be able to link its library dependencies.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func librariesSearchPaths(path: AbsolutePath, name: String) -> [AbsolutePath]

    /// Returns all the include paths of the library dependencies form the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func librariesSwiftIncludePaths(path: AbsolutePath, name: String) -> [AbsolutePath]

    /// Returns the list of products that should be embedded into the product of the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func embeddableFrameworks(path: AbsolutePath, name: String) throws -> [GraphDependencyReference]

    /// Returns that are added to a dummy copy files phase to enforce build order between dependencies that Xcode doesn't usually respect (e.g. Resouce Bundles)
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - target: Target.
    func copyProductDependencies(path: AbsolutePath, target: Target) -> [GraphDependencyReference]

    /// For the given project it returns all its expected dependency references.
    /// This method is useful to know which references should be added to the products directory in the generated project.
    /// - Parameter project: Project whose dependency references will be returned.
    func allDependencyReferences(for project: Project) throws -> [GraphDependencyReference]

    /// Finds all the app extension dependencies for the target at the given path with the given name.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func appExtensionDependencies(path: AbsolutePath, name: String) -> [TargetNode]

    /// Depth-first search (DFS) is an algorithm for traversing graph data structures. It starts at a source node
    /// and explores as far as possible along each branch before backtracking.
    ///
    /// This implementation looks for TargetNode's and traverses their dependencies so that we are able to build
    /// up a graph of dependencies to later be used to define the "Link Binary with Library" in an xcodeproj.
    func findAll<T: GraphNode>(path: AbsolutePath) -> Set<T>

    /// Find a target with the given name and in the given directory.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func findTargetNode(path: AbsolutePath, name: String) -> TargetNode?

    /// Returns all the transitive dependencies of the given target that are static libraries.
    /// - Parameter targetNode: Target node whose transitive static libraries will be returned.
    func transitiveStaticTargetNodes(for targetNode: TargetNode) -> Set<TargetNode>

    /// Retuns the first host target node for a given target node
    ///
    /// (e.g. finding host application for an extension)
    ///
    /// - Parameter path: Path of the hosted target
    /// - Parameter name: Name of the hosted target
    ///
    /// - Note: Search is limited to nodes with a matching path (i.e. targets within the same project)
    func hostTargetNodeFor(path: AbsolutePath, name: String) -> TargetNode?
}

// swiftlint:disable:next type_body_length
public class Graph: Graphing {
    // MARK: - Attributes

    private let cache: GraphLoaderCaching
    public let name: String
    public let entryPath: AbsolutePath
    public let entryNodes: [GraphNode]

    // MARK: - Init

    public convenience init(name: String, entryPath: AbsolutePath, cache: GraphLoaderCaching) {
        self.init(name: name,
                  entryPath: entryPath,
                  cache: cache,
                  entryNodes: [])
    }

    init(name: String,
         entryPath: AbsolutePath,
         cache: GraphLoaderCaching,
         entryNodes: [GraphNode]) {
        self.name = name
        self.entryPath = entryPath
        self.cache = cache
        self.entryNodes = entryNodes
    }

    // MARK: - Encodable

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var nodes: [GraphNode] = []

        nodes.append(contentsOf: cache.targetNodes.values.flatMap { $0.values })
        nodes.append(contentsOf: Array(cache.precompiledNodes.values))

        try container.encode(nodes.sorted(by: { $0.path < $1.path }))
    }

    // MARK: - Graphing

    public var projects: [Project] {
        Array(cache.projects.values)
    }

    public var projectPaths: [AbsolutePath] {
        Array(cache.projects.keys)
    }

    public var cocoapods: [CocoaPodsNode] {
        Array(cache.cocoapodsNodes.values)
    }

    public var packages: [PackageNode] {
        cache.packages.values.flatMap { $0 }
    }

    public var frameworks: [FrameworkNode] {
        cache.precompiledNodes.values.compactMap { $0 as? FrameworkNode }
    }

    public var precompiled: [PrecompiledNode] {
        Array(cache.precompiledNodes.values)
    }

    public var targets: [TargetNode] {
        cache.targetNodes.flatMap { $0.value.values }
    }

    public func targets(at path: AbsolutePath) -> [TargetNode] {
        guard let nodes = cache.targetNodes[path] else {
            return []
        }
        return Array(nodes.values)
    }

    public func target(path: AbsolutePath, name: String) -> TargetNode? {
        findTargetNode(path: path, name: name)
    }

    public func targetDependencies(path: AbsolutePath, name: String) -> [TargetNode] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.targetDependencies
            .filter { $0.path == path }
    }

    public func testTargetsDependingOn(path: AbsolutePath, name: String) -> [TargetNode] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }
        return targets(at: path)
            .filter { $0.target.product.testsBundle }
            .filter { $0.targetDependencies.contains(targetNode) }
            .sorted { $0.target.name < $1.target.name }
    }

    public func staticDependencies(path: AbsolutePath, name: String) -> [GraphDependencyReference] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.targetDependencies
            .filter(isStaticLibrary)
            .map(productDependencyReference)
    }

    public func resourceBundleDependencies(path: AbsolutePath, name: String) -> [TargetNode] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.targetDependencies
            .filter { $0.target.product == .bundle }
    }

    public func packages(path: AbsolutePath, name _: String) throws -> [PackageNode] {
        cache.packages[path] ?? []
    }

    public func linkableDependencies(path: AbsolutePath, name: String) throws -> [GraphDependencyReference] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        var references = Set<GraphDependencyReference>()

        // System libraries and frameworks

        if targetNode.target.canLinkStaticProducts() {
            let transitiveSystemLibraries = transitiveStaticTargetNodes(for: targetNode).flatMap {
                $0.sdkDependencies.map {
                    GraphDependencyReference.sdk(path: $0.path, status: $0.status)
                }
            }

            references = references.union(transitiveSystemLibraries)
        }

        let directSystemLibrariesAndFrameworks = targetNode.sdkDependencies.map {
            GraphDependencyReference.sdk(path: $0.path, status: $0.status)
        }

        references = references.union(directSystemLibrariesAndFrameworks)

        // Precompiled libraries and frameworks

        let precompiledLibrariesAndFrameworks = targetNode.precompiledDependencies
            .lazy
            .map(GraphDependencyReference.init)

        references = references.union(precompiledLibrariesAndFrameworks)

        // Static libraries and frameworks / Static libraries' dynamic libraries

        if targetNode.target.canLinkStaticProducts() {
            var staticLibraryTargetNodes = transitiveStaticTargetNodes(for: targetNode)

            // Exclude any static products linked in a host application
            if targetNode.target.product == .unitTests {
                if let hostApp = hostApplication(for: targetNode) {
                    staticLibraryTargetNodes.subtract(transitiveStaticTargetNodes(for: hostApp))
                }
            }

            let staticLibraries = staticLibraryTargetNodes.map(productDependencyReference)

            let staticDependenciesDynamicLibraries = staticLibraryTargetNodes.flatMap {
                $0.targetDependencies
                    .filter(or(isFramework, isDynamicLibrary))
                    .map(productDependencyReference)
            }

            references = references.union(staticLibraries + staticDependenciesDynamicLibraries)
        }

        // Link dynamic libraries and frameworks

        let dynamicLibrariesAndFrameworks = targetNode.targetDependencies
            .filter(or(isFramework, isDynamicLibrary))
            .map(productDependencyReference)

        references = references.union(dynamicLibrariesAndFrameworks)
        return Array(references).sorted()
    }

    public func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.libraryDependencies
            .map(\.publicHeaders)
    }

    public func librariesSearchPaths(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.libraryDependencies
            .map { $0.path.removingLastComponent() }
    }

    public func librariesSwiftIncludePaths(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.libraryDependencies
            .compactMap { $0.swiftModuleMap?.removingLastComponent() }
    }

    public func embeddableFrameworks(path: AbsolutePath, name: String) throws -> [GraphDependencyReference] {
        guard let targetNode = findTargetNode(path: path, name: name),
            canEmbedProducts(targetNode: targetNode) else {
            return []
        }

        var references: Set<GraphDependencyReference> = Set([])

        let isDynamicAndLinkable = { (node: PrecompiledNode) -> Bool in
            if let framework = node as? FrameworkNode { return framework.linking == .dynamic }
            if let xcframework = node as? XCFrameworkNode { return xcframework.linking == .dynamic }
            return false
        }

        /// Precompiled frameworks
        let precompiledFrameworks = findAll(targetNode: targetNode, test: isDynamicAndLinkable, skip: canEmbedProducts)
            .lazy
            .map(GraphDependencyReference.init)

        references.formUnion(precompiledFrameworks)

        /// Other targets' frameworks.
        let otherTargetFrameworks = findAll(targetNode: targetNode, test: isFramework, skip: canEmbedProducts)
            .map(productDependencyReference)

        references.formUnion(otherTargetFrameworks)

        // Exclude any products embed in unit test host apps
        if targetNode.target.product == .unitTests {
            if let hostApp = hostApplication(for: targetNode) {
                references.subtract(try embeddableFrameworks(path: hostApp.path, name: hostApp.name))
            }
        }

        return references.sorted()
    }

    public func copyProductDependencies(path: AbsolutePath, target: Target) -> [GraphDependencyReference] {
        var dependencies = [GraphDependencyReference]()

        if target.product.isStatic {
            dependencies.append(contentsOf: staticDependencies(path: path, name: target.name))
        }

        dependencies.append(contentsOf:
            resourceBundleDependencies(path: path, name: target.name)
                .map(productDependencyReference))

        return Set(dependencies).sorted()
    }

    public func allDependencyReferences(for project: Project) throws -> [GraphDependencyReference] {
        let linkableDependencies = try project.targets.flatMap {
            try self.linkableDependencies(path: project.path, name: $0.name)
        }

        let embeddableDependencies = try project.targets.flatMap {
            try self.embeddableFrameworks(path: project.path, name: $0.name)
        }

        let copyProductDependencies = project.targets.flatMap {
            self.copyProductDependencies(path: project.path, target: $0)
        }

        let allDepdendencies = linkableDependencies + embeddableDependencies + copyProductDependencies
        return Set(allDepdendencies).sorted()
    }

    public func appExtensionDependencies(path: AbsolutePath, name: String) -> [TargetNode] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        let validProducts: [Product] = [
            .appExtension, .stickerPackExtension, .watch2Extension,
        ]

        return targetNode.targetDependencies
            .filter { validProducts.contains($0.target.product) }
    }

    public func findAll<T: GraphNode>(path: AbsolutePath) -> Set<T> {
        guard let targetNodes = cache.targetNodes[path] else {
            return []
        }

        var references = Set<T>()

        for (_, node) in targetNodes {
            references.formUnion(findAll(targetNode: node))
        }

        return references
    }

    public func findAll<T: GraphNode, S: GraphNode>(targetNode: TargetNode,
                                                    test: (T) -> Bool = { _ in true },
                                                    skip: (S) -> Bool = { _ in false }) -> Set<T> {
        var stack = Stack<GraphNode>()

        stack.push(targetNode)

        var visited: Set<GraphNode> = .init()
        var references = Set<T>()

        while !stack.isEmpty {
            guard let node = stack.pop() else {
                continue
            }

            if visited.contains(node) {
                continue
            }

            visited.insert(node)

            if node != targetNode, let matchingNode = node as? T, test(matchingNode) {
                references.insert(matchingNode)
            }

            if node != targetNode, let node = node as? S, skip(node) {
                continue
            } else if let targetNode = node as? TargetNode {
                for child in targetNode.dependencies where !visited.contains(child) {
                    stack.push(child)
                }
            }
        }

        return references
    }

    public func findTargetNode(path: AbsolutePath, name: String) -> TargetNode? {
        func isPathAndNameEqual(node: TargetNode) -> Bool {
            node.path == path && node.target.name == name
        }

        let targetNodes = entryNodes.compactMap { $0 as? TargetNode }

        if let targetNode = targetNodes.first(where: isPathAndNameEqual) {
            return targetNode
        }

        guard let cachedTargetNodesForPath = cache.targetNodes[path] else {
            return nil
        }

        return cachedTargetNodesForPath[name]
    }

    public func transitiveStaticTargetNodes(for targetNode: TargetNode) -> Set<TargetNode> {
        findAll(targetNode: targetNode,
                test: isStaticLibrary,
                skip: canLinkStaticProducts)
    }

    public func hostTargetNodeFor(path: AbsolutePath, name: String) -> TargetNode? {
        guard let cachedTargetNodesForPath = cache.targetNodes[path] else {
            return nil
        }
        return cachedTargetNodesForPath.values.first {
            $0.dependencies.contains(where: { $0.path == path && $0.name == name })
        }
    }

    // MARK: - Fileprivate

    fileprivate func productDependencyReference(for targetNode: TargetNode) -> GraphDependencyReference {
        .product(target: targetNode.target.name, productName: targetNode.target.productNameWithExtension)
    }

    fileprivate func hostApplication(for targetNode: TargetNode) -> TargetNode? {
        targetDependencies(path: targetNode.path, name: targetNode.name)
            .first(where: { $0.target.product == .app })
    }

    fileprivate func isStaticLibrary(targetNode: TargetNode) -> Bool {
        targetNode.target.product.isStatic
    }

    fileprivate func isDynamicLibrary(targetNode: TargetNode) -> Bool {
        targetNode.target.product == .dynamicLibrary
    }

    fileprivate func isFramework(targetNode: TargetNode) -> Bool {
        targetNode.target.product == .framework
    }

    fileprivate func canLinkStaticProducts(targetNode: TargetNode) -> Bool {
        targetNode.target.canLinkStaticProducts()
    }

    fileprivate func canEmbedProducts(targetNode: TargetNode) -> Bool {
        let validProducts: [Product] = [
            .app,
            .unitTests,
            .uiTests,
            .watch2Extension,
        ]

        return validProducts.contains(targetNode.target.product)
    }
}
