import Foundation
import TSCBasic
import TuistGraph
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

// swiftlint:disable:next type_body_length
public class Graph: Encodable, Equatable {
    // MARK: - Attributes

    /// Name of the graph.
    public let name: String

    /// Path to the directory where the graph has been loaded from.
    public let entryPath: AbsolutePath

    /// The entry nodes of the graph.
    public let entryNodes: [GraphNode]

    /// Workspace of the graph
    public let workspace: Workspace

    /// Projects of the graph
    public let projects: [Project]

    /// Dictionary whose keys are paths to directories where projects are defined, and the values are the CocoaPods nodes define in them.
    /// If none of the nodes of the graph references a CocoaPods node, the node gets released from memory.
    public let cocoapods: [CocoaPodsNode]

    /// Dictionary whose keys are path to directories where projects are defined, and the values are packages defined in that project.
    /// If none of the nodes of the graph references a Package node, the node gets released from memory.
    public let packages: [PackageNode]

    /// Dictionary whose keys are path to directories where projects are defined, and the values are precompiled nodes defined in them.
    /// If none of the nodds references a precompiled node, the node gets released from memory.
    public let precompiled: [PrecompiledNode]

    /// Returns all the frameorks that are part of the graph.
    public var frameworks: [FrameworkNode] { precompiled.compactMap { $0 as? FrameworkNode } }

    /// Dictionary whose keys are path to directories where projects are defined, and the values are target nodes defined in them.
    public let targets: [AbsolutePath: [TargetNode]]

    /// Schemes of the graph
    public var schemes: [Scheme] {
        projects.flatMap(\.schemes) + workspace.schemes
    }

    // MARK: - Init

    convenience init(
        name: String,
        entryPath: AbsolutePath,
        cache: GraphLoaderCaching,
        entryNodes: [GraphNode],
        workspace: Workspace
    ) {
        self.init(
            name: name,
            entryPath: entryPath,
            entryNodes: entryNodes,
            workspace: workspace,
            projects: Array(cache.projects.values),
            cocoapods: Array(cache.cocoapodsNodes.values),
            packages: Array(cache.packages.flatMap(\.value)),
            precompiled: Array(cache.precompiledNodes.values),
            targets: cache.targetNodes.mapValues { Array($0.values) }
        )
    }

    public init(
        name: String,
        entryPath: AbsolutePath,
        entryNodes: [GraphNode],
        workspace: Workspace,
        projects: [Project],
        cocoapods: [CocoaPodsNode],
        packages: [PackageNode],
        precompiled: [PrecompiledNode],
        targets: [AbsolutePath: [TargetNode]]
    ) {
        self.name = name
        self.entryPath = entryPath
        self.entryNodes = entryNodes
        self.workspace = workspace
        self.projects = projects
        self.cocoapods = cocoapods
        self.packages = packages
        self.precompiled = precompiled
        self.targets = targets
    }

    // MARK: - Encodable

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var nodes: [GraphNode] = []

        nodes.append(contentsOf: targets.values.flatMap { targets in targets.compactMap { $0 } })
        nodes.append(contentsOf: precompiled.compactMap { $0 })

        try container.encode(nodes.sorted(by: { $0.path < $1.path }))
    }

    /// Returns the target with the given name and at the given directory.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    public func target(path: AbsolutePath, name: String) -> TargetNode? {
        findTargetNode(path: path, name: name)
    }

    /// Returns all target nodes at a given path (i.e. all target nodes in a project)
    /// - Parameters:
    ///   - path: Path to the directory where the project is located
    public func targets(at path: AbsolutePath) -> [TargetNode] {
        Array(targets[path] ?? [])
    }

    /// Returns all the non-transitive target dependencies for the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    public func targetDependencies(path: AbsolutePath, name: String) -> [TargetNode] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.targetDependencies
            .filter { $0.path == path }
    }

    /// Returns all test targets directly dependent on the given target
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    public func testTargetsDependingOn(path: AbsolutePath, name: String) -> [TargetNode] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }
        return targets[path]?.compactMap { $0 }
            .filter { $0.target.product.testsBundle }
            .filter { $0.targetDependencies.contains(targetNode) }
            .sorted { $0.target.name < $1.target.name } ?? []
    }

    /// Returns all non-transitive target static dependencies for the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    public func staticDependencies(path: AbsolutePath, name: String) -> [GraphDependencyReference] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.targetDependencies
            .filter(isStaticLibrary)
            .map(productDependencyReference)
    }
    
    /// Returns the transitive resource bundle dependencies for the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    ///   - allowNonSupportingTargets: Allow to search non-supporting targets.
    public func resourceBundleDependencies(path: AbsolutePath, name: String, allowNonSupportingTargets: Bool = false) -> [TargetNode] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }
        
        guard targetNode.target.supportsResources || allowNonSupportingTargets else {
            return []
        }
        
        let canHostResources: (TargetNode) -> Bool = {
            $0.target.supportsResources
        }

        let isBundle: (TargetNode) -> Bool = {
            $0.target.product == .bundle
        }

        let bundles = findAll(targetNode: targetNode, test: isBundle, skip: canHostResources)

        return bundles.sorted {
            $0.target.name < $1.target.name
        }
    }

    /// It returns the libraries a given target should be linked against.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    public func linkableDependencies(path: AbsolutePath, name: String) throws -> [GraphDependencyReference] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        var references = Set<GraphDependencyReference>()

        // System libraries and frameworks

        if targetNode.target.canLinkStaticProducts() {
            let transitiveSystemLibraries = transitiveStaticTargetNodes(for: targetNode).flatMap {
                $0.sdkDependencies.map {
                    GraphDependencyReference.sdk(path: $0.path, status: $0.status, source: $0.source)
                }
            }

            references = references.union(transitiveSystemLibraries)
        }

        if targetNode.target.isAppClip {
            let path = try SDKNode.appClip(status: .required).path
            references.insert(GraphDependencyReference.sdk(path: path,
                                                           status: .required,
                                                           source: .system))
        }

        let directSystemLibrariesAndFrameworks = targetNode.sdkDependencies.map {
            GraphDependencyReference.sdk(path: $0.path, status: $0.status, source: $0.source)
        }

        references = references.union(directSystemLibrariesAndFrameworks)

        // Precompiled libraries and frameworks

        let precompiledLibrariesAndFrameworks = targetNode.recursivePrecompiledDependencies
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

    /// Returns the paths for the given target to be able to import the headers from its library dependencies.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    public func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.libraryDependencies
            .map(\.publicHeaders)
    }

    /// Returns the search paths for the given target to be able to link its library dependencies.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    public func librariesSearchPaths(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.libraryDependencies
            .map { $0.path.removingLastComponent() }
    }

    /// Returns all the include paths of the library dependencies form the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    public func librariesSwiftIncludePaths(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        return targetNode.libraryDependencies
            .compactMap { $0.swiftModuleMap?.removingLastComponent() }
    }

    /// Returns all runpath search paths of the given target
    /// Currently applied only to test targets with no host application
    /// - Parameters:
    ///     - path; Path to the directory where the project that defines the target
    ///     - name: Name of the target
    public func runPathSearchPaths(path: AbsolutePath, name: String) -> [AbsolutePath] {
        guard
            let targetNode = findTargetNode(path: path, name: name),
            canEmbedProducts(targetNode: targetNode),
            targetNode.target.product == .unitTests,
            hostApplication(for: targetNode) == nil
        else {
            return []
        }

        var references: Set<AbsolutePath> = Set([])

        /// Precompiled frameworks
        let precompiledFrameworkNodes: Set<PrecompiledNode> = findAll(targetNode: targetNode,
                                                                      test: { $0.isDynamicAndLinkable() },
                                                                      skip: canEmbedProducts)
        let precompiledFrameworks = precompiledFrameworkNodes
            .lazy
            .map(\.path)
            .map(\.parentDirectory)

        references.formUnion(precompiledFrameworks)

        return references.sorted()
    }

    /// Returns the list of products that should be embedded into the product of the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    public func embeddableFrameworks(path: AbsolutePath, name: String) -> [GraphDependencyReference] {
        guard let targetNode = findTargetNode(path: path, name: name),
            canEmbedProducts(targetNode: targetNode)
        else {
            return []
        }

        var references: Set<GraphDependencyReference> = Set([])

        /// Precompiled frameworks
        let precompiledFrameworkNodes: Set<PrecompiledNode> = findAll(targetNode: targetNode,
                                                                      test: { $0.isDynamicAndLinkable() },
                                                                      skip: canEmbedProducts)

        let precompiledFrameworks = precompiledFrameworkNodes
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
                references.subtract(embeddableFrameworks(path: hostApp.path, name: hostApp.name))
            } else {
                references = []
            }
        }

        return references.sorted()
    }

    /// Returns that are added to a dummy copy files phase to enforce build order between dependencies that Xcode doesn't usually respect (e.g. Resouce Bundles)
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - target: Target.
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

    /// For the given project it returns all its expected dependency references.
    /// This method is useful to know which references should be added to the products directory in the generated project.
    /// - Parameter project: Project whose dependency references will be returned.
    public func allDependencyReferences(for project: Project) throws -> [GraphDependencyReference] {
        let linkableDependencies = try project.targets.flatMap {
            try self.linkableDependencies(path: project.path, name: $0.name)
        }

        let embeddableDependencies = project.targets.flatMap {
            self.embeddableFrameworks(path: project.path, name: $0.name)
        }

        let copyProductDependencies = project.targets.flatMap {
            self.copyProductDependencies(path: project.path, target: $0)
        }

        let allDepdendencies = linkableDependencies + embeddableDependencies + copyProductDependencies
        return Set(allDepdendencies).sorted()
    }

    /// Finds all the app extension dependencies for the target at the given path with the given name.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    public func appExtensionDependencies(path: AbsolutePath, name: String) -> [TargetNode] {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return []
        }

        let validProducts: [Product] = [
            .appExtension, .stickerPackExtension, .watch2Extension, .messagesExtension,
        ]

        return targetNode.targetDependencies
            .filter { validProducts.contains($0.target.product) }
    }

    public func appClipDependencies(path: AbsolutePath, name: String) -> TargetNode? {
        guard let targetNode = findTargetNode(path: path, name: name) else {
            return nil
        }

        return targetNode.targetDependencies.first { $0.target.product == .appClip }
    }

    /// Depth-first search (DFS) is an algorithm for traversing graph data structures. It starts at a source node
    /// and explores as far as possible along each branch before backtracking.
    ///
    /// This implementation looks for TargetNode's and traverses their dependencies so that we are able to build
    /// up a graph of dependencies to later be used to define the "Link Binary with Library" in an xcodeproj.
    public func findAll<T: GraphNode>(path: AbsolutePath) -> Set<T> {
        guard let targetNodes = targets[path] else {
            return []
        }

        var references = Set<T>()

        targetNodes.forEach { node in
            references.formUnion(findAll(targetNode: node))
        }

        return references
    }

    public func findAll<T: GraphNode, S: GraphNode>(targetNode: TargetNode,
                                                    test: (T) -> Bool = { _ in true },
                                                    skip: (S) -> Bool = { _ in false }) -> Set<T>
    {
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
            } else if let xcframeworkNode = node as? XCFrameworkNode {
                for child in xcframeworkNode.dependencies.map(\.node) where !visited.contains(child) {
                    stack.push(child)
                }
            } else if let frameworkNode = node as? FrameworkNode {
                for child in frameworkNode.dependencies.map(\.node) where !visited.contains(child) {
                    stack.push(child)
                }
            }
        }

        return references
    }

    /// Find a target with the given name and in the given directory.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    public func findTargetNode(path: AbsolutePath, name: String) -> TargetNode? {
        func isPathAndNameEqual(node: TargetNode) -> Bool {
            node.project.path == path && node.target.name == name
        }

        let targetNodes = entryNodes.compactMap { $0 as? TargetNode }

        if let targetNode = targetNodes.first(where: isPathAndNameEqual) {
            return targetNode
        }

        guard let cachedTargetNodesForPath = targets[path] else {
            return nil
        }

        return cachedTargetNodesForPath.first(where: { $0.name == name }) ?? nil
    }

    /// Returns all the transitive dependencies of the given target that are static libraries.
    /// - Parameter targetNode: Target node whose transitive static libraries will be returned.
    public func transitiveStaticTargetNodes(for targetNode: TargetNode) -> Set<TargetNode> {
        findAll(targetNode: targetNode,
                test: isStaticLibrary,
                skip: canLinkStaticProducts)
    }

    /// Retuns the first host target node for a given target node
    ///
    /// (e.g. finding host application for an extension)
    ///
    /// - Parameter path: Path of the hosted target
    /// - Parameter name: Name of the hosted target
    ///
    /// - Note: Search is limited to nodes with a matching path (i.e. targets within the same project)
    public func hostTargetNodeFor(path: AbsolutePath, name: String) -> TargetNode? {
        guard let cachedTargetNodesForPath = targets[path] else {
            return nil
        }
        return cachedTargetNodesForPath.first { node in
            node.dependencies.contains(where: { $0.path == path && $0.name == name })
        } ?? nil
    }

    /// - Returns: Host application for a given `targetNode`, if it exists
    public func hostApplication(for targetNode: TargetNode) -> TargetNode? {
        targetDependencies(path: targetNode.path, name: targetNode.name)
            .first(where: { $0.target.product == .app })
    }

    /// Returns a copy of the graph with the given projects set.
    /// - Parameter projects: Projects to be set to the copy.
    public func with(projects: [Project]) -> Graph {
        Graph(
            name: name,
            entryPath: entryPath,
            entryNodes: entryNodes,
            workspace: workspace,
            projects: projects,
            cocoapods: cocoapods,
            packages: packages,
            precompiled: precompiled,
            targets: targets
        )
    }

    /// Returns a copy of the graph with the given targets.
    /// - Parameter targets: Targets to be set to the copy.
    /// - Returns: New graph with the given targets.
    public func with(targets: [AbsolutePath: [TargetNode]]) -> Graph {
        Graph(
            name: name,
            entryPath: entryPath,
            entryNodes: entryNodes,
            workspace: workspace,
            projects: projects,
            cocoapods: cocoapods,
            packages: packages,
            precompiled: precompiled,
            targets: targets
        )
    }

    /// Returns a copy of the graph with a given workspace.
    /// - Parameter workspace: Workspace to be set to the copy.
    /// - Returns: New graph with a given workspace.
    public func with(workspace: Workspace) -> Graph {
        Graph(
            name: name,
            entryPath: entryPath,
            entryNodes: entryNodes,
            workspace: workspace,
            projects: projects,
            cocoapods: cocoapods,
            packages: packages,
            precompiled: precompiled,
            targets: targets
        )
    }

    public func forEach(closure: (GraphNode) -> Void) {
        var stack = Stack<GraphNode>()

        targets.flatMap(\.value).forEach { stack.push($0) }

        var visited: Set<GraphNode> = .init()

        while !stack.isEmpty {
            guard let node = stack.pop() else {
                continue
            }

            if visited.contains(node) {
                continue
            }

            closure(node)

            visited.insert(node)

            if let targetNode = node as? TargetNode {
                for child in targetNode.dependencies where !visited.contains(child) {
                    stack.push(child)
                }
            } else if let xcframeworkNode = node as? XCFrameworkNode {
                for child in xcframeworkNode.dependencies.map(\.node) where !visited.contains(child) {
                    stack.push(child)
                }
            } else if let frameworkNode = node as? FrameworkNode {
                for child in frameworkNode.dependencies where !visited.contains(child.node) {
                    stack.push(child.node)
                }
            }
        }
    }

    // MARK: - Fileprivate

    fileprivate func productDependencyReference(for targetNode: TargetNode) -> GraphDependencyReference {
        .product(target: targetNode.target.name, productName: targetNode.target.productNameWithExtension)
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

    // MARK: - Equatable

    public static func == (lhs: Graph, rhs: Graph) -> Bool {
        lhs.name == rhs.name &&
            lhs.entryPath == rhs.entryPath &&
            lhs.entryNodes == rhs.entryNodes &&
            lhs.projects == rhs.projects &&
            lhs.cocoapods == rhs.cocoapods &&
            lhs.packages == rhs.packages &&
            lhs.precompiled == rhs.precompiled &&
            lhs.frameworks == rhs.frameworks &&
            lhs.targets == rhs.targets
    }
}
