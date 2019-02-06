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

enum DependencyReference: Equatable {
    case absolute(AbsolutePath)
    case product(String)

    static func == (lhs: DependencyReference, rhs: DependencyReference) -> Bool {
        switch (lhs, rhs) {
        case let (.absolute(lhsPath), .absolute(rhsPath)):
            return lhsPath == rhsPath
        case let (.product(lhsName), .product(rhsName)):
            return lhsName == rhsName
        default:
            return false
        }
    }
}

protocol Graphing: AnyObject {
    var name: String { get }
    var entryPath: AbsolutePath { get }
    var entryNodes: [GraphNode] { get }
    var projects: [Project] { get }
    var frameworks: [FrameworkNode] { get }

    func linkableDependencies(path: AbsolutePath, name: String) throws -> [DependencyReference]
    func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> [AbsolutePath]
    func embeddableFrameworks(path: AbsolutePath, name: String, system: Systeming) throws -> [DependencyReference]
    func targetDependencies(path: AbsolutePath, name: String) -> [String]
    func staticLibraryDependencies(path: AbsolutePath, name: String) -> [DependencyReference]

    // MARK: - Depth First Search

    /// Depth-first search (DFS) is an algorithm for traversing graph data structures. It starts at a source node
    /// and explores as far as possible along each branch before backtracking.
    ///
    /// This implementation looks for TargetNode's and traverses their dependencies so that we are able to build
    /// up a graph of dependencies to later be used to define the "Link Binary with Library" in an xcodeproj.

    func findAll<T: GraphNode>(path: AbsolutePath) -> Set<T>
    func findAll<T: GraphNode>(path: AbsolutePath, test: (T) -> Bool) -> Set<T>
    func findAll<T: GraphNode>(path: AbsolutePath, name: String, test: (T) -> Bool) -> Set<T>
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

    func targetDependencies(path: AbsolutePath, name: String) -> [String] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.targetDependencies
            .filter { $0.path == path }
            .map(\.target.name)
    }

    func staticLibraryDependencies(path: AbsolutePath, name: String) -> [DependencyReference] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.targetDependencies
            .filter(isStaticLibrary)
            .map(\.target.productName)
            .map(DependencyReference.product)
    }

    func linkableDependencies(path: AbsolutePath, name: String) throws -> [DependencyReference] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        var references: [DependencyReference] = []

        /// Precompiled libraries and frameworks

        let precompiledLibrariesAndFrameworks = targetNode.precompiledDependencies
            .map(\.path)
            .map(DependencyReference.absolute)

        references.append(contentsOf: precompiledLibrariesAndFrameworks)

        switch targetNode.target.product {
        case .staticLibrary, .dynamicLibrary, .framework:
            // Ignore the products, they do not want to directly link the static libraries, the top level bundles will be responsible.
            break
        case .app, .unitTests, .uiTests:

            let staticLibraries = findAll(targetNode: targetNode, test: isStaticLibrary)
                .lazy
                .map(\.target.productName)
                .map(DependencyReference.product)

            references.append(contentsOf: staticLibraries)
        }

        // Link dynamic libraries and frameworks

        let dynamicLibrariesAndFrameworks = targetNode.targetDependencies
            .filter(or(isFramework, isDynamicLibrary))
            .map(\.target.productName)
            .map(DependencyReference.product)

        references.append(contentsOf: dynamicLibrariesAndFrameworks)

        return references
    }

    func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.libraryDependencies
            .map(\.publicHeaders)
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
            .uiTests
//            .tvExtension,
//            .appExtension,
//            .watchExtension,
//            .watch2Extension,
//            .messagesExtension,
//            .watchApp,
//            .watch2App,
//            .messagesApplication,
        ]

        if validProducts.contains(targetNode.target.product) == false {
            return []
        }

        var references: [DependencyReference] = []

        /// Precompiled frameworks
        let precompiledFrameworks = findAll(targetNode: targetNode, test: frameworkUsesDynamicLinking(system: system))
            .lazy
            .map(\.path)
            .map(DependencyReference.absolute)

        references.append(contentsOf: precompiledFrameworks)

        /// Other targets' frameworks.
        let otherTargetFrameworks = findAll(targetNode: targetNode, test: isFramework)
            .lazy
            .map(\.target.productName)
            .map(DependencyReference.product)

        references.append(contentsOf: otherTargetFrameworks)

        return references
    }

    // MARK: - Fileprivate

    fileprivate func findTargetNode(path: AbsolutePath, name: String) -> TargetNode? {
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
        return targetNode.target.product == .staticLibrary
    }

    internal func isDynamicLibrary(targetNode: TargetNode) -> Bool {
        return targetNode.target.product == .dynamicLibrary
    }

    internal func isFramework(targetNode: TargetNode) -> Bool {
        return targetNode.target.product == .framework
    }

    internal func frameworkUsesDynamicLinking(system: Systeming) -> (_ frameworkNode: FrameworkNode) -> Bool {
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
}

extension Graph {
    internal func findAll<T: GraphNode>(path: AbsolutePath) -> Set<T> {
        let alwaysTrue: (T) -> Bool = { _ in true }
        return findAll(path: path, test: alwaysTrue)
    }

    // Traverse the graph for all cached target nodes using DFS and return all results passing the test.
    internal func findAll<T: GraphNode>(path: AbsolutePath, test: (T) -> Bool) -> Set<T> {
        guard let targetNodes = cache.targetNodes[path] else {
            return []
        }

        var references = Set<T>()

        for (_, node) in targetNodes {
            references.formUnion(findAll(targetNode: node, test: test))
        }

        return references
    }

    // Traverse the graph finding target node with name using DFS and return all results passing the test.
    internal func findAll<T: GraphNode>(path: AbsolutePath, name: String, test: (T) -> Bool) -> Set<T> {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return findAll(targetNode: targetNode, test: test)
    }

    // Traverse the graph from the target node using DFS and return all results passing the test.
    internal func findAll<T: GraphNode>(targetNode: TargetNode, test: (T) -> Bool) -> Set<T> {
        var stack = Stack<GraphNode>()

        for node in targetNode.dependencies where node is T {
            // swiftlint:disable:next force_cast
            stack.push(node as! T)
        }

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
            if node is T, test(node as! T) {
                // swiftlint:disable:next force_cast
                references.insert(node as! T)
            }

            if let targetNode = node as? TargetNode {
                for child in targetNode.dependencies where !visited.contains(child) {
                    stack.push(child)
                }
            }
        }

        return references
    }
}
