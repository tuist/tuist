import Foundation
import TSCBasic
import TuistSupport

public protocol ValueGraphTraversing {
    init(graph: ValueGraph)

    /// Given a project directory and target name, it returns all its direct target dependencies.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func directTargetDependencies(path: AbsolutePath, name: String) -> [Target]
    
    
    /// Given a project directory and a target name, it returns all the dependencies that are extensions.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func appExtensionDependencies(path: AbsolutePath, name: String) -> [Target]
    
    /// Returns the transitive resource bundle dependencies for the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func resourceBundleDependencies(path: AbsolutePath, name: String) -> [Target]
    
    /// Given a dependency, it returns the target if the dependency represents a target and the
    /// target exists in the graph.
    /// - Parameter from: Dependency.
    func target(from: ValueGraphDependency) -> Target?
}

public class ValueGraphTraverser: ValueGraphTraversing {
    private let graph: ValueGraph

    public required init(graph: ValueGraph) {
        self.graph = graph
    }

    public func directTargetDependencies(path: AbsolutePath, name: String) -> [Target] {
        guard let dependencies = graph.dependencies[.target(name: name, path: path)] else { return [] }
        return dependencies.flatMap { (dependency) -> [Target] in
            guard case let ValueGraphDependency.target(dependencyName, dependencyPath) = dependency else { return [] }
            guard let projectDependencies = graph.targets[dependencyPath], let dependencyTarget = projectDependencies[dependencyName] else { return []
            }
            return [dependencyTarget]
        }.sorted()
    }
    
    public func resourceBundleDependencies(path: AbsolutePath, name: String) -> [Target] {
        guard let target = self.graph.targets[path]?[name] else { return [] }
        guard target.supportsResources else { return [] }
        
        let canHostResources: (ValueGraphDependency) -> Bool = {
            self.target(from: $0)?.supportsResources == true
        }

        let isBundle: (ValueGraphDependency) -> Bool = {
            self.target(from: $0)?.product == .bundle
        }
        
        let bundles = findAll(rootNode: .target(name: name, path: path),
                              test: isBundle,
                              skip: canHostResources)
        let bundleTargets = bundles.compactMap(target(from:))

        return bundleTargets.sorted()
    }
    
    public func target(from dependency: ValueGraphDependency) -> Target? {
        guard case let ValueGraphDependency.target(name, path) = dependency else {
            return nil
        }
        return self.graph.targets[path]?[name]
    }
    
    public func appExtensionDependencies(path: AbsolutePath, name: String) -> [Target] {
        let validProducts: [Product] = [
            .appExtension, .stickerPackExtension, .watch2Extension, .messagesExtension,
        ]
        return directTargetDependencies(path: path, name: name)
            .filter({ validProducts.contains($0.product)})
            .sorted()
    }
    
    /// Depth-first search (DFS) is an algorithm for traversing graph data structures. It starts at a source node
    /// and explores as far as possible along each branch before backtracking.
    ///
    /// This implementation looks for TargetNode's and traverses their dependencies so that we are able to build
    /// up a graph of dependencies to later be used to define the "Link Binary with Library" in an xcodeproj.
    public func findAll(path: AbsolutePath) -> Set<ValueGraphDependency> {
        guard let targets = graph.targets[path]?.values else { return Set() }
        
        
        var references = Set<ValueGraphDependency>()
        
        targets.forEach { target in
            references.formUnion(findAll(rootNode: ValueGraphDependency.target(name: target.name, path: path)))
        }
        
        return references
    }
    
    fileprivate func findAll(rootNode: ValueGraphDependency,
                             test: (ValueGraphDependency) -> Bool = { _ in true },
                             skip: (ValueGraphDependency) -> Bool = { _ in false }) -> Set<ValueGraphDependency> {
        var stack = Stack<ValueGraphDependency>()
        
        stack.push(rootNode)
        
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
            
            if node != rootNode, test(node) {
                references.insert(node)
            }
            
            if node != rootNode, skip(node) {
                continue
            }
            
            graph.dependencies[node]?.forEach({ (nodeDependency) in
                if !visited.contains(nodeDependency) {
                    stack.push(nodeDependency)
                }
            })
        }
        
        return references
    }

}
