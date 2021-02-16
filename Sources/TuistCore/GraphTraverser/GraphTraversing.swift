import Foundation
import TSCBasic
import TuistGraph

public protocol GraphTraversing {
    /// Graph name
    var name: String { get }

    /// Returns true if the project has package dependencies.
    var hasPackages: Bool { get }

    /// Returns true if the graph has remote packages.
    var hasRemotePackages: Bool { get }

    /// The path to the directory from where the graph has been loaded.
    var path: AbsolutePath { get }

    /// Returns the graph's workspace.
    var workspace: Workspace { get }

    /// Returns the graph projects.
    var projects: [AbsolutePath: Project] { get }

    /// Returns all the targets of the graph.
    var targets: [AbsolutePath: [String: Target]] { get }

    /// Dependencies.
    var dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] { get }

    /// Returns all the apps from the graph.
    func apps() -> Set<ValueGraphTarget>

    /// - Returns: All the schemes of the graph
    func schemes() -> [Scheme]

    /// Returns the targets from the project that lives in the directory from which the graph has been loaded.
    func rootTargets() -> Set<ValueGraphTarget>

    /// Returns all the targets of the project.
    func allTargets() -> Set<ValueGraphTarget>

    /// Returns the paths to directories containing a Podfile
    func cocoapodsPaths() -> Set<AbsolutePath>

    /// Returns the project from which the graph has been loaded.
    func rootProjects() -> Set<Project>

    /// Returns the list of all the pre-compiled frameworks that are part of the graph.
    func precompiledFrameworksPaths() -> Set<AbsolutePath>

    /// Returns all the targets of a given product.
    /// - Parameter product: Product.
    func targets(product: Product) -> Set<ValueGraphTarget>

    /// It returns the target with the given name in the project that is defined in the given directory path.
    /// - Parameters:
    ///   - path: Path to the directory that contains the definition of the project with the target is defined.
    ///   - name: Name of the target.
    func target(path: AbsolutePath, name: String) -> ValueGraphTarget?

    /// It returns the targets of the project defined in the directory at the given path.
    /// - Parameter path: Path to the directory that contains the definition of the project.
    func targets(at path: AbsolutePath) -> Set<ValueGraphTarget>

    /// Given a project directory and target name, it returns all its direct target dependencies.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func directTargetDependencies(path: AbsolutePath, name: String) -> Set<ValueGraphTarget>

    /// Given a project directory and a target name, it returns all the dependencies that are extensions.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func appExtensionDependencies(path: AbsolutePath, name: String) -> Set<ValueGraphTarget>

    /// Returns the transitive resource bundle dependencies for the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func resourceBundleDependencies(path: AbsolutePath, name: String) -> Set<ValueGraphTarget>

    /// Returns the list of test targets that depend on the one with the given name at the given path.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project definition.
    ///   - name: Name of the target whose dependant test targets will be returned.
    func testTargetsDependingOn(path: AbsolutePath, name: String) -> Set<ValueGraphTarget>

    /// Returns all non-transitive target static dependencies for the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func directStaticDependencies(path: AbsolutePath, name: String) -> Set<GraphDependencyReference>

    /// Given a project directory and a target name, it returns an appClips dependency.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func appClipDependencies(path: AbsolutePath, name: String) -> ValueGraphTarget?

    /// Given a project directory and a target name, it returns the list of dependencies that need to be embedded into the target product.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func embeddableFrameworks(path: AbsolutePath, name: String) -> Set<GraphDependencyReference>

    /// Given a project directory and a target name, it returns the list of dependencies that need to be linked from the target.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func linkableDependencies(path: AbsolutePath, name: String) throws -> Set<GraphDependencyReference>

    /// Given a project directory and a target name, it returns a list of dependencies that need to be included in a copy files build phase
    ///
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name
    func copyProductDependencies(path: AbsolutePath, name: String) -> Set<GraphDependencyReference>

    /// Given a project directory and a target name, it returns the list of header folders that should be exposed to the target.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name
    func librariesPublicHeadersFolders(path: AbsolutePath, name: String) -> Set<AbsolutePath>

    /// Given a project directory and a target name, it returns the list of library folders that should be exposed to the target.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func librariesSearchPaths(path: AbsolutePath, name: String) -> Set<AbsolutePath>

    /// Given a project directory and a target name, it returns the list of foldres with Swift modules that should be expoed to the target.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func librariesSwiftIncludePaths(path: AbsolutePath, name: String) -> Set<AbsolutePath>

    /// Returns all runpath search paths of the given target
    /// Currently applied only to test targets with no host application
    /// - Parameters:
    ///     - path; Path to the directory where the project that defines the target
    ///     - name: Name of the target
    func runPathSearchPaths(path: AbsolutePath, name: String) -> Set<AbsolutePath>

    /// It returns the host target for the given target.
    /// - Parameters:
    ///     - path; Path to the directory where the project that defines the target
    ///     - name: Name of the target
    func hostTargetFor(path: AbsolutePath, name: String) -> ValueGraphTarget?

    /// For the project at the given path, it returns all the dependencies that should
    /// be referenced from the project. This method is intended to be used when generating
    /// the groups.
    /// - Parameter path: Path to the directory where the project is defined.
    func allProjectDependencies(path: AbsolutePath) throws -> Set<GraphDependencyReference>

    /// Returns true if the given target depends on XCTest.
    /// - Parameters:
    ///   - path: Path to the project tha defines the target.
    ///   - name: Target name.
    func dependsOnXCTest(path: AbsolutePath, name: String) -> Bool
}

public extension GraphTraversing {
    func apps() -> Set<ValueGraphTarget> {
        targets(product: .app)
    }
}
