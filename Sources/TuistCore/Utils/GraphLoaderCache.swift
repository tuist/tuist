import Basic
import Foundation

/// Graph loader cache.
public class GraphLoaderCache: GraphLoaderCaching {
    // MARK: - GraphLoaderCaching

    var tuistConfigs: [AbsolutePath: TuistConfig] = [:]
    public var projects: [AbsolutePath: Project] = [:]
    public var packages: [AbsolutePath: [PackageNode]] = [:]
    public var precompiledNodes: [AbsolutePath: PrecompiledNode] = [:]
    public var targetNodes: [AbsolutePath: [String: TargetNode]] = [:]

    /// Cached CocoaPods nodes
    public var cocoapodsNodes: [AbsolutePath: CocoaPodsNode] = [:]

    /// Returns, if it exists, the CocoaPods node at the given path.
    ///
    /// - Parameter path: Path to the directory where the Podfile is defined.
    /// - Returns: The CocoaPods node if it exists in the cache.
    public func cocoapods(_ path: AbsolutePath) -> CocoaPodsNode? {
        return cocoapodsNodes[path]
    }

    /// Adds a parsed CocoaPods graph node to the cache.
    ///
    /// - Parameter cocoapods: Node to be added to the cache.
    public func add(cocoapods: CocoaPodsNode) {
        cocoapodsNodes[cocoapods.path] = cocoapods
    }

    /// Cached SwiftPM package nodes
    public var packageNodes: [AbsolutePath: PackageProductNode] = [:]

    /// Returns, if it exists, the Package node at the given path.
    ///
    /// - Parameter path: Path to the directory where the Podfile is defined.
    /// - Returns: The Package node if it exists in the cache.
    public func package(_ path: AbsolutePath) -> PackageProductNode? {
        return packageNodes[path]
    }

    /// Adds a parsed Package graph node to the cache.
    ///
    /// - Parameter package: Node to be added to the cache.
    public func add(package: PackageProductNode) {
        packageNodes[package.path] = package
    }

    public func tuistConfig(_ path: AbsolutePath) -> TuistConfig? {
        return tuistConfigs[path]
    }

    public func add(tuistConfig: TuistConfig, path: AbsolutePath) {
        tuistConfigs[path] = tuistConfig
    }

    public func project(_ path: AbsolutePath) -> Project? {
        return projects[path]
    }

    public func add(project: Project) {
        projects[project.path] = project
        packages[project.path] = project.packages.map { PackageNode(package: $0, path: project.path) }
    }

    public func add(precompiledNode: PrecompiledNode) {
        precompiledNodes[precompiledNode.path] = precompiledNode
    }

    public func precompiledNode(_ path: AbsolutePath) -> PrecompiledNode? {
        return precompiledNodes[path]
    }

    public func add(targetNode: TargetNode) {
        var projectTargets: [String: TargetNode]! = targetNodes[targetNode.path]
        if projectTargets == nil { projectTargets = [:] }
        projectTargets[targetNode.target.name] = targetNode
        targetNodes[targetNode.path] = projectTargets
    }

    public func targetNode(_ path: AbsolutePath, name: String) -> TargetNode? {
        return targetNodes[path]?[name]
    }
}
