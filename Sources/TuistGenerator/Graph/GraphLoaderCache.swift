import Basic
import Foundation

protocol GraphLoaderCaching: AnyObject {
    var projects: [AbsolutePath: Project] { get }
    var targetNodes: [AbsolutePath: [String: TargetNode]] { get }
    var precompiledNodes: [AbsolutePath: PrecompiledNode] { get }

    func project(_ path: AbsolutePath) -> Project?
    func add(project: Project)
    func add(precompiledNode: PrecompiledNode)
    func precompiledNode(_ path: AbsolutePath) -> PrecompiledNode?
    func add(targetNode: TargetNode)
    func targetNode(_ path: AbsolutePath, name: String) -> TargetNode?
    func tuistConfig(_ path: AbsolutePath) -> TuistConfig?
    func add(tuistConfig: TuistConfig, path: AbsolutePath)

    /// Cached CocoaPods nodes
    var cocoapodsNodes: [AbsolutePath: CocoaPodsNode] { get }

    /// Returns, if it exists, the CocoaPods node at the given path.
    ///
    /// - Parameter path: Path to the directory where the Podfile is defined.
    /// - Returns: The CocoaPods node if it exists in the cache.
    func cocoapods(_ path: AbsolutePath) -> CocoaPodsNode?

    /// Adds a parsed CocoaPods graph node to the cache.
    ///
    /// - Parameter cocoapods: Node to be added to the cache.
    func add(cocoapods: CocoaPodsNode)

    var packages: [AbsolutePath: [PackageNode]] { get }

    var packageNodes: [AbsolutePath: PackageProductNode] { get }
    func package(_ path: AbsolutePath) -> PackageProductNode?
    func add(package: PackageProductNode)
}

/// Graph loader cache.
class GraphLoaderCache: GraphLoaderCaching {
    // MARK: - GraphLoaderCaching

    var tuistConfigs: [AbsolutePath: TuistConfig] = [:]
    var projects: [AbsolutePath: Project] = [:]
    var packages: [AbsolutePath: [PackageNode]] = [:]
    var precompiledNodes: [AbsolutePath: PrecompiledNode] = [:]
    var targetNodes: [AbsolutePath: [String: TargetNode]] = [:]

    /// Cached CocoaPods nodes
    var cocoapodsNodes: [AbsolutePath: CocoaPodsNode] = [:]

    /// Returns, if it exists, the CocoaPods node at the given path.
    ///
    /// - Parameter path: Path to the directory where the Podfile is defined.
    /// - Returns: The CocoaPods node if it exists in the cache.
    func cocoapods(_ path: AbsolutePath) -> CocoaPodsNode? {
        return cocoapodsNodes[path]
    }

    /// Adds a parsed CocoaPods graph node to the cache.
    ///
    /// - Parameter cocoapods: Node to be added to the cache.
    func add(cocoapods: CocoaPodsNode) {
        cocoapodsNodes[cocoapods.path] = cocoapods
    }

    /// Cached SwiftPM package nodes
    var packageNodes: [AbsolutePath: PackageProductNode] = [:]

    /// Returns, if it exists, the Package node at the given path.
    ///
    /// - Parameter path: Path to the directory where the Podfile is defined.
    /// - Returns: The Package node if it exists in the cache.
    func package(_ path: AbsolutePath) -> PackageProductNode? {
        return packageNodes[path]
    }

    /// Adds a parsed Package graph node to the cache.
    ///
    /// - Parameter package: Node to be added to the cache.
    func add(package: PackageProductNode) {
        packageNodes[package.path] = package
    }

    func tuistConfig(_ path: AbsolutePath) -> TuistConfig? {
        return tuistConfigs[path]
    }

    func add(tuistConfig: TuistConfig, path: AbsolutePath) {
        tuistConfigs[path] = tuistConfig
    }

    func project(_ path: AbsolutePath) -> Project? {
        return projects[path]
    }

    func add(project: Project) {
        projects[project.path] = project
        packages[project.path] = project.packages.map { PackageNode(package: $0, path: project.path) }
    }

    func add(precompiledNode: PrecompiledNode) {
        precompiledNodes[precompiledNode.path] = precompiledNode
    }

    func precompiledNode(_ path: AbsolutePath) -> PrecompiledNode? {
        return precompiledNodes[path]
    }

    func add(targetNode: TargetNode) {
        var projectTargets: [String: TargetNode]! = targetNodes[targetNode.path]
        if projectTargets == nil { projectTargets = [:] }
        projectTargets[targetNode.target.name] = targetNode
        targetNodes[targetNode.path] = projectTargets
    }

    func targetNode(_ path: AbsolutePath, name: String) -> TargetNode? {
        return targetNodes[path]?[name]
    }
}
