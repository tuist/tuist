import Basic
import Foundation
import TuistCore

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

enum DependencyReference: Equatable, Comparable, Hashable {
    case absolute(AbsolutePath)
    case product(target: String)
    case sdk(AbsolutePath, SDKStatus)

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .absolute(path):
            hasher.combine(path)
        case let .product(target):
            hasher.combine(target)
        case let .sdk(path, status):
            hasher.combine(path)
            hasher.combine(status)
        }
    }

    static func == (lhs: DependencyReference, rhs: DependencyReference) -> Bool {
        switch (lhs, rhs) {
        case let (.absolute(lhsPath), .absolute(rhsPath)):
            return lhsPath == rhsPath
        case let (.product(lhsName), .product(rhsName)):
            return lhsName == rhsName
        case let (.sdk(lhsPath, lhsStatus), .sdk(rhsPath, rhsStatus)):
            return lhsPath == rhsPath && lhsStatus == rhsStatus
        default:
            return false
        }
    }

    static func < (lhs: DependencyReference, rhs: DependencyReference) -> Bool {
        switch (lhs, rhs) {
        case let (.absolute(lhsPath), .absolute(rhsPath)):
            return lhsPath < rhsPath
        case let (.product(lhsName), .product(rhsName)):
            return lhsName < rhsName
        case let (.sdk(lhsPath, _), .sdk(rhsPath, _)):
            return lhsPath < rhsPath
        case (.sdk, .absolute):
            return true
        case (.sdk, .product):
            return true
        case (.product, .absolute):
            return true
        default:
            return false
        }
    }
}

protocol Graphing: AnyObject, Encodable {
    var name: String { get }
    var entryPath: AbsolutePath { get }
    var entryNodes: [GraphNode] { get }
    var projects: [Project] { get }
    var frameworks: [FrameworkNode] { get }

    /// Returns all the precompiled nodes that are part of the graph.
    var precompiled: [PrecompiledNode] { get }

    /// Returns all the targets that are part of the graph.
    var targets: [TargetNode] { get }

    func linkableDependencies(path: AbsolutePath, name: String, system: Systeming) throws -> [DependencyReference]
    func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> [AbsolutePath]
    func librariesSearchPaths(path: AbsolutePath, name: String) -> [AbsolutePath]
    func librariesSwiftIncludePaths(path: AbsolutePath, name: String) -> [AbsolutePath]
    func embeddableFrameworks(path: AbsolutePath, name: String, system: Systeming) throws -> [DependencyReference]
    func targetDependencies(path: AbsolutePath, name: String) -> [TargetNode]
    func staticDependencies(path: AbsolutePath, name: String) -> [DependencyReference]
    func resourceBundleDependencies(path: AbsolutePath, name: String) -> [TargetNode]

    // MARK: - Depth First Search

    /// Depth-first search (DFS) is an algorithm for traversing graph data structures. It starts at a source node
    /// and explores as far as possible along each branch before backtracking.
    ///
    /// This implementation looks for TargetNode's and traverses their dependencies so that we are able to build
    /// up a graph of dependencies to later be used to define the "Link Binary with Library" in an xcodeproj.

    func findAll<T: GraphNode>(path: AbsolutePath) -> Set<T>
}

class Graph: Graphing {
    // MARK: - Attributes

    private let cache: GraphLoaderCaching
    let name: String
    let entryPath: AbsolutePath
    let entryNodes: [GraphNode]

    var projects: [Project] {
        return Array(cache.projects.values)
    }

    var projectPaths: [AbsolutePath] {
        return Array(cache.projects.keys)
    }

    // MARK: - Init

    init(name: String,
         entryPath: AbsolutePath,
         cache: GraphLoaderCaching,
         entryNodes: [GraphNode]) {
        self.name = name
        self.entryPath = entryPath
        self.cache = cache
        self.entryNodes = entryNodes
    }

    // MARK: - Internal

    var frameworks: [FrameworkNode] {
        return cache.precompiledNodes.values.compactMap { $0 as? FrameworkNode }
    }

    /// Returns all the precompiled nodes that are part of the graph.
    var precompiled: [PrecompiledNode] {
        return Array(cache.precompiledNodes.values)
    }

    /// Returns all the targets that are part of the graph.
    var targets: [TargetNode] {
        return cache.targetNodes.flatMap { $0.value.values }
    }

    func targetDependencies(path: AbsolutePath, name: String) -> [TargetNode] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.targetDependencies
            .filter { $0.path == path }
    }

    func staticDependencies(path: AbsolutePath, name: String) -> [DependencyReference] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.targetDependencies
            .filter(isStaticLibrary)
            .map { DependencyReference.product(target: $0.target.name) }
    }

    func resourceBundleDependencies(path: AbsolutePath, name: String) -> [TargetNode] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.targetDependencies
            .filter { $0.target.product == .bundle }
    }

    func linkableDependencies(path: AbsolutePath, name: String, system _: Systeming) throws -> [DependencyReference] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        var references = Set<DependencyReference>()

        // System libraries and frameworks
        
        if targetNode.target.canLinkStaticProducts() {
            let transitiveSystemLibraries = findAll(targetNode: targetNode, test: isStaticLibrary, skip: isFramework).flatMap {
                $0.sdkDependencies.map {
                    DependencyReference.sdk($0.path, $0.status)
                }
            }
            
            references = references.union(transitiveSystemLibraries)
        }
        
        let directSystemLibrariesAndFrameworks = targetNode.sdkDependencies.map {
            DependencyReference.sdk($0.path, $0.status)
        }
        
        references = references.union(directSystemLibrariesAndFrameworks)

        // Precompiled libraries and frameworks

        let precompiledLibrariesAndFrameworks = targetNode.precompiledDependencies
            .lazy
            .map(\.path)
            .map(DependencyReference.absolute)

        references = references.union(precompiledLibrariesAndFrameworks)

        // Static libraries and frameworks

        if targetNode.target.canLinkStaticProducts() {
            let staticLibraries = findAll(targetNode: targetNode, test: isStaticLibrary, skip: isFramework)
                .map { DependencyReference.product(target: $0.target.name) }

            references = references.union(staticLibraries)
        }

        // Link dynamic libraries and frameworks

        let dynamicLibrariesAndFrameworks = targetNode.targetDependencies
            .filter(or(isFramework, isDynamicLibrary))
            .map { DependencyReference.product(target: $0.target.name) }

        references = references.union(dynamicLibrariesAndFrameworks)

        return Array(references).sorted()
    }

    func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.libraryDependencies
            .map(\.publicHeaders)
    }

    func librariesSearchPaths(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.libraryDependencies
            .map { $0.path.removingLastComponent() }
    }

    func librariesSwiftIncludePaths(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.libraryDependencies
            .compactMap { $0.swiftModuleMap?.removingLastComponent() }
    }

    func embeddableFrameworks(path: AbsolutePath,
                              name: String,
                              system: Systeming) throws -> [DependencyReference] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        let validProducts: [Product] = [
            .app,
            .unitTests,
            .uiTests,
        ]

        if validProducts.contains(targetNode.target.product) == false {
            return []
        }

        var references: [DependencyReference] = []

        let isDynamicAndLinkable = frameworkUsesDynamicLinking(system: system)

        /// Precompiled frameworks
        let precompiledFrameworks = findAll(targetNode: targetNode, test: isDynamicAndLinkable)
            .lazy
            .map(\.path)
            .map(DependencyReference.absolute)

        references.append(contentsOf: precompiledFrameworks)

        /// Other targets' frameworks.
        let otherTargetFrameworks = findAll(targetNode: targetNode, test: isFramework)
            .map { DependencyReference.product(target: $0.target.name) }

        references.append(contentsOf: otherTargetFrameworks)

        /// Pre-built frameworks
        let transitiveFrameworks = findAll(targetNode: targetNode)
            .lazy
            .filter(FrameworkNode.self)
            .map(\.path)
            .map(DependencyReference.absolute)

        references.append(contentsOf: transitiveFrameworks)

        return Set(references).sorted()
    }

    // MARK: - Fileprivate

    private func findTargetNode(path: AbsolutePath, name: String) -> TargetNode? {
        func isPathAndNameEqual(node: TargetNode) -> Bool {
            return node.path == path && node.target.name == name
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
}

// MARK: - Predicates

extension Graph {
    internal func isStaticLibrary(targetNode: TargetNode) -> Bool {
        return targetNode.target.product.isStatic
    }

    internal func isDynamicLibrary(targetNode: TargetNode) -> Bool {
        return targetNode.target.product == .dynamicLibrary
    }

    internal func isFramework(targetNode: TargetNode) -> Bool {
        return targetNode.target.product == .framework
    }

    internal func frameworkUsesDynamicLinking(system: Systeming) -> (_ frameworkNode: PrecompiledNode) -> Bool {
        return { frameworkNode in
            let isDynamicLink = try? frameworkNode.linking(system: system) == .dynamic
            return isDynamicLink ?? false
        }
    }
}

// MARK: - TargetNode helper computed properties, provide lazy arrays by default.

extension TargetNode {
    fileprivate var targetDependencies: [TargetNode] {
        return dependencies.lazy.compactMap { $0 as? TargetNode }
    }

    fileprivate var precompiledDependencies: [PrecompiledNode] {
        return dependencies.lazy.compactMap { $0 as? PrecompiledNode }
    }

    fileprivate var libraryDependencies: [LibraryNode] {
        return dependencies.lazy.compactMap { $0 as? LibraryNode }
    }

    fileprivate var frameworkDependencies: [FrameworkNode] {
        return dependencies.lazy.compactMap { $0 as? FrameworkNode }
    }

    fileprivate var sdkDependencies: [SDKNode] {
        return dependencies.lazy.compactMap { $0 as? SDKNode }
    }
}

extension Graph {
    func findAll<T: GraphNode>(path: AbsolutePath) -> Set<T> {
        guard let targetNodes = cache.targetNodes[path] else {
            return []
        }

        var references = Set<T>()

        for (_, node) in targetNodes {
            references.formUnion(findAll(targetNode: node))
        }

        return references
    }

    // Traverse the graph from the target node using DFS and return all results passing the test.
    func findAll<T: GraphNode>(targetNode: TargetNode, test: (T) -> Bool = { _ in true }, skip: (T) -> Bool = { _ in false }) -> Set<T> {
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

            // swiftlint:disable:next force_cast
            if node != targetNode, node is T, test(node as! T) {
                // swiftlint:disable:next force_cast
                references.insert(node as! T)
            }

            if node != targetNode, let node = node as? T, skip(node) {
                continue
            } else if let targetNode = node as? TargetNode {
                for child in targetNode.dependencies where !visited.contains(child) {
                    stack.push(child)
                }
            }
        }

        return references
    }
}

// MARK: - Encodable

extension Graph {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var nodes: [GraphNode] = []

        nodes.append(contentsOf: cache.targetNodes.values.flatMap { $0.values })
        nodes.append(contentsOf: Array(cache.precompiledNodes.values))

        try container.encode(nodes.sorted(by: { $0.path < $1.path }))
    }
}
