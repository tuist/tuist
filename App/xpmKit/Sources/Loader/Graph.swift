import Basic
import Foundation

/// Graph error.
///
/// - unsupportedFileExtension: thrown when the file extension cannot be obtained for the given product.
enum GraphError: FatalError {
    case unsupportedFileExtension(String)

    /// Error description.
    var description: String {
        switch self {
        case let .unsupportedFileExtension(productType):
            return "Could't obtain product file extension for product type: \(productType)"
        }
    }

    /// Error type
    var type: ErrorType {
        switch self {
        case .unsupportedFileExtension:
            return .bugSilent
        }
    }
}

/// Dependency reference.
///
/// - absolute: the reference is an absolute path to the dependency.
/// - product: the reference is the name of it in the products directory.
enum DependencyReference: Equatable {
    case absolute(AbsolutePath)
    case product(String)

    /// Returns true if two instances of DependencyReference are equal.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
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

/// Protocol that represents a graph.
protocol Graphing: AnyObject {
    var name: String { get }
    var entryPath: AbsolutePath { get }
    var cache: GraphLoaderCaching { get }
    var entryNodes: [GraphNode] { get }
    var projects: [Project] { get }
    func linkableDependencies(path: AbsolutePath, name: String) throws -> [DependencyReference]
    func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> [AbsolutePath]
    func embeddableFrameworks(path: AbsolutePath, name: String, shell: Shelling) throws -> [DependencyReference]
    func dependencies(path: AbsolutePath, name: String) -> Set<GraphNode>
    func dependencies(path: AbsolutePath) -> Set<GraphNode>
    func targetDependencies(path: AbsolutePath, name: String) -> [String]
}

/// Graph representation.
class Graph: Graphing {
    /// Graph name.
    let name: String

    /// Entry path (directory)
    let entryPath: AbsolutePath

    /// Cache.
    let cache: GraphLoaderCaching

    /// Entry nodes.
    let entryNodes: [GraphNode]

    /// Graph projects.
    var projects: [Project] {
        return Array(cache.projects.values)
    }

    /// Initializes the graph with its attributes.
    ///
    /// - Parameters:
    ///   - name: graph name.
    ///   - entryPath: path to the folder that contains the entry point manifest.
    ///   - cache: graph cache.
    ///   - entryNodes: nodes that are defined in the entry point manifest.
    init(name: String,
         entryPath: AbsolutePath,
         cache: GraphLoaderCaching,
         entryNodes: [GraphNode]) {
        self.name = name
        self.entryPath = entryPath
        self.cache = cache
        self.entryNodes = entryNodes
    }

    /// Returns all the dependencies of a project.
    ///
    /// - Parameter path: path to the folder where the project is defined.
    /// - Returns: list of dependencies.
    func dependencies(path: AbsolutePath) -> Set<GraphNode> {
        var dependencies: Set<GraphNode> = Set()
        cache.targetNodes[path]?.forEach {
            dependencies.formUnion(self.dependencies(path: path, name: $0.key))
        }
        return dependencies
    }

    /// Returns the list of dependencies that a given target is dependent on.
    /// Thes list includes the direct dependencies and the dependencyes of those at any level.
    ///
    /// - Parameters:
    ///   - path: path to the folder that contains the project definition.
    ///   - name: target name.
    /// - Returns: list of dependencies.
    func dependencies(path: AbsolutePath, name: String) -> Set<GraphNode> {
        var dependencies: Set<GraphNode> = Set()
        var add: ((GraphNode) -> Void)!
        add = { node in
            guard let targetNode = node as? TargetNode else { return }
            targetNode.dependencies.forEach({ dependencies.insert($0) })
            targetNode.dependencies.compactMap({ $0 as? TargetNode }).forEach(add)
        }
        if let target = cache.targetNodes[path]?[name] {
            add(target)
        }
        return dependencies
    }

    /// Returns the dependencies of a given target that are in the same project.
    /// This is useful to generate the target dependencies in the Xcode project.
    ///
    /// - Parameters:
    ///   - path: path to the folder that contains the manifest where the target is defined.
    ///   - name: target name.
    /// - Returns: name of the targets.
    func targetDependencies(path: AbsolutePath, name: String) -> [String] {
        guard let targetNodes = cache.targetNodes[path] else { return [] }
        guard let targetNode = targetNodes[name] else { return [] }
        return targetNode.dependencies
            .compactMap({ $0 as? TargetNode })
            .filter({ $0.path == path })
            .map({ $0.target.name })
    }

    /// Given a target, it returns the list of dependencies that should be linked from it.
    ///
    /// - Parameters:
    ///   - path: path to the folder that contains the manifest where the target is defined.
    ///   - name: target name.
    /// - Returns: paths to the linkable dependencies (.framework & .a)
    func linkableDependencies(path: AbsolutePath, name: String) throws -> [DependencyReference] {
        guard let targetNodes = cache.targetNodes[path] else { return [] }
        guard let targetNode = targetNodes[name] else { return [] }

        var references: [DependencyReference] = []

        /// Precompiled libraries and frameworks
        references.append(contentsOf: targetNode
            .dependencies
            .compactMap({ $0 as? PrecompiledNode })
            .map({ DependencyReference.absolute($0.path) }))

        /// Other targets frameworks and libraries
        try references.append(contentsOf: targetNode
            .dependencies
            .compactMap({ $0 as? TargetNode })
            .filter({ $0.target.isLinkable() })
            .map({ targetNode in
                let xcodeProduct = targetNode.target.product.xcodeValue
                guard let `extension` = xcodeProduct.fileExtension else {
                    throw GraphError.unsupportedFileExtension(xcodeProduct.rawValue)
                }
                return DependencyReference.product("\(targetNode.target.name).\(`extension`)")
        }))

        return references
    }

    /// Given a target, it returns the list of public headers folders that should be
    /// exposed to the target.
    ///
    /// - Parameters:
    ///   - path: path to the folder that contains the manifest where the target is defined.
    ///   - name: target name.
    /// - Returns: paths to the public headers folders.
    func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard let targetNodes = cache.targetNodes[path] else { return [] }
        guard let targetNode = targetNodes[name] else { return [] }
        return targetNode
            .dependencies
            .compactMap({ $0 as? LibraryNode })
            .map({ $0.publicHeaders })
    }

    /// Given a target, it returns the list of frameworks that should be embedded into the
    /// frameworks folder of the target product.
    ///
    /// - Parameters:
    ///   - path: path to the folder that contains the manifest where the target is defined.
    ///   - name: target name.
    ///   - shell: shell util.
    /// - Returns: paths to the frameworks that should be embedded.
    /// - Throws: an error is thrown while trying to get whether a framework is static or dynamic.
    func embeddableFrameworks(path: AbsolutePath,
                              name: String,
                              shell: Shelling) throws -> [DependencyReference] {
        guard let targetNodes = cache.targetNodes[path] else { return [] }
        guard let targetNode = targetNodes[name] else { return [] }

        /// If the target is not an app we shouldn't embed anything.
        if targetNode.target.product != .app { return [] }

        var references: [DependencyReference] = []
        let dependencies = self.dependencies(path: path, name: name)

        /// Precompiled frameworks
        references.append(contentsOf: try dependencies
            .compactMap({ $0 as? FrameworkNode })
            .filter({ try $0.linking(shell: shell) == .dynamic })
            .map({ DependencyReference.absolute($0.path) }))

        /// Other targets' frameworks.
        try references.append(contentsOf: dependencies
            .compactMap({ $0 as? TargetNode })
            .filter({ $0.target.product == .framework })
            .map({ targetNode in
                let xcodeProduct = targetNode.target.product.xcodeValue
                guard let `extension` = xcodeProduct.fileExtension else {
                    throw GraphError.unsupportedFileExtension(xcodeProduct.rawValue)
                }
                return DependencyReference.product("\(targetNode.target.name).\(`extension`)")
        }))
        return references
    }
}
