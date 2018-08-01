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

class Graph: Graphing {

    // MARK: - Attributes

    let name: String
    let entryPath: AbsolutePath
    let cache: GraphLoaderCaching
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

    func dependencies(path: AbsolutePath) -> Set<GraphNode> {
        var dependencies: Set<GraphNode> = Set()
        cache.targetNodes[path]?.forEach {
            dependencies.formUnion(self.dependencies(path: path, name: $0.key))
        }
        return dependencies
    }

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

    func targetDependencies(path: AbsolutePath, name: String) -> [String] {
        guard let targetNodes = cache.targetNodes[path] else { return [] }
        guard let targetNode = targetNodes[name] else { return [] }
        return targetNode.dependencies
            .compactMap({ $0 as? TargetNode })
            .filter({ $0.path == path })
            .map({ $0.target.name })
    }

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

    func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard let targetNodes = cache.targetNodes[path] else { return [] }
        guard let targetNode = targetNodes[name] else { return [] }
        return targetNode
            .dependencies
            .compactMap({ $0 as? LibraryNode })
            .map({ $0.publicHeaders })
    }

    func embeddableFrameworks(path: AbsolutePath,
                              name: String,
                              shell: Shelling) throws -> [DependencyReference] {
        guard let targetNodes = cache.targetNodes[path] else { return [] }
        guard let targetNode = targetNodes[name] else { return [] }

        let validProducts: [Product] = [
            .app,
            .unitTests,
            .uiTests,
            .tvExtension,
            .appExtension,
            .watchExtension,
            .watch2Extension,
            .messagesExtension,
            .watchApp,
            .watch2App,
            .messagesApplication,
        ]

        if !validProducts.contains(targetNode.target.product) { return [] }

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
