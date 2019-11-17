import Basic
import Foundation

public protocol GraphLoaderCaching: AnyObject {
    // MARK: - Projects

    /// A dictionary where the key is the path to the directory that contains the project
    /// and the value is the project manifest.
    var projects: [AbsolutePath: Project] { get }

    /// If a project at the given path exists in the cache it returns it.
    /// - Parameter path: Path to the directory that contains the project.
    func project(_ path: AbsolutePath) -> Project?

    /// Adds the given project to the cache.
    /// - Parameter project: Project representation.
    func add(project: Project)

    // MARK: - Precompiled

    /// Adds the given precompiled node to the cache.
    /// - Parameter precompiledNode: Node to be added to the cache.
    func add(precompiledNode: PrecompiledNode)

    /// If a precompiled node exists at the given path, it returns it.
    /// - Parameter path: Path to the precompiled node.
    func precompiledNode(_ path: AbsolutePath) -> PrecompiledNode?

    /// A dictionary where the key is the path to a precomiled node (e.g. a framework)
    /// and the value is the representation of the precompiled node.
    var precompiledNodes: [AbsolutePath: PrecompiledNode] { get }

    // MARK: - Targets

    /// A dictionary where the key is the path to the directory that contains the project
    /// where the target is defined and the value is a dictionary with the name of the target
    /// as the key, and the target node as the value.
    var targetNodes: [AbsolutePath: [String: TargetNode]] { get }

    /// Adds the given target node to the cache.
    /// - Parameter targetNode: Target node representation.
    func add(targetNode: TargetNode)

    /// If a target node exists at the given project's directory path it returns it.
    /// - Parameters:
    ///   - path: Path to the directory of the project that contains the target.
    ///   - name: Name of the target.
    func targetNode(_ path: AbsolutePath, name: String) -> TargetNode?

    // MARK: - TuistConfig

    /// It returns a Tuist configuration if it exists at the given directory.
    /// - Parameter path: Path to the directory that contains the TuistConfig.
    func tuistConfig(_ path: AbsolutePath) -> TuistConfig?

    /// Caches a TuistConfig representation.
    /// - Parameters:
    ///   - tuistConfig: Tuist configuration.
    ///   - path: Path to the directory that contains th
    func add(tuistConfig: TuistConfig, path: AbsolutePath)

    // MARK: - CocoaPods

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

    // MARK: - Packages

    /// A dictionary where the key is the path to the directory that contains
    /// the project where the package is defined, and the value the list of packages
    /// defined in that project.
    var packages: [AbsolutePath: [PackageNode]] { get }

    /// A dictionary where the key is the path to the directory that contains
    /// the project where the package products are defined and the value
    /// the list of packages.
    var packageNodes: [AbsolutePath: PackageProductNode] { get }

    /// Returns a package if it exists for the project at the given path.
    /// - Parameter path: Path to the directory that contains the project.
    func package(_ path: AbsolutePath) -> PackageProductNode?

    /// Adds a package product to the cache.
    /// - Parameter package: Package product.
    func add(package: PackageProductNode)
}
