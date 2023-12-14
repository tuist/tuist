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
    var dependencies: [GraphDependency: Set<GraphDependency>] { get }

    /// Returns all the apps from the graph.
    func apps() -> Set<GraphTarget>

    /// - Returns: All the schemes of the graph
    func schemes() -> [Scheme]

    /// Returns the targets from the project that lives in the directory from which the graph has been loaded.
    func rootTargets() -> Set<GraphTarget>

    /// Returns all the targets of the project.
    func allTargets() -> Set<GraphTarget>

    /// Returns all the targets of the project, topological sorted.
    func allTargetsTopologicalSorted() throws -> [GraphTarget]

    /// Returns all the internal targets, that is, excluding `Dependencies`.
    func allInternalTargets() -> Set<GraphTarget>

    /// - Returns: All the test plans of the graph
    func allTestPlans() -> Set<TestPlan>

    /// Returns the project from which the graph has been loaded.
    func rootProjects() -> Set<Project>

    /// Returns the list of all the pre-compiled frameworks that are part of the graph.
    func precompiledFrameworksPaths() -> Set<AbsolutePath>

    /// Returns all the targets of a given product.
    /// - Parameter product: Product.
    func targets(product: Product) -> Set<GraphTarget>

    /// It returns the target with the given name in the project that is defined in the given directory path.
    /// - Parameters:
    ///   - path: Path to the directory that contains the definition of the project with the target is defined.
    ///   - name: Name of the target.
    func target(path: AbsolutePath, name: String) -> GraphTarget?

    /// It returns the targets of the project defined in the directory at the given path.
    /// - Parameter path: Path to the directory that contains the definition of the project.
    func targets(at path: AbsolutePath) -> Set<GraphTarget>

    /// - Returns: The test plans with the given name.
    func testPlan(name: String) -> TestPlan?

    /// Given a project directory and target name, it returns **all**l its direct target dependencies present in the same project.
    /// If you want only direct target dependencies present in the same project as the target, use `directLocalTargetDependencies`
    /// instead
    /// - Parameters:
    ///   - path: Path to the directory that contains the target's project.
    ///   - name: Target name.
    func directTargetDependencies(path: AbsolutePath, name: String) -> Set<GraphTarget>

    /// Given a project directory and target name, it returns all its direct target dependencies present in the same project.
    /// To get **all** direct target dependencies use the method `directTargetDependencies` instead
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func directLocalTargetDependencies(path: AbsolutePath, name: String) -> Set<GraphTarget>

    /// Given a project directory and a target name, it returns all direct local dependencies with their conditions
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func directLocalTargetDependenciesWithConditions(path: AbsolutePath, name: String) -> [(
        GraphTarget,
        PlatformCondition?
    )]

    /// Given a project directory and a target name, it returns all direct dependencies with their conditions
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func directTargetDependenciesWithConditions(path: AbsolutePath, name: String) -> [(GraphTarget, PlatformCondition?)]

    /// Given a project directory and a target name, it returns all the dependencies that are extensions.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func appExtensionDependencies(path: AbsolutePath, name: String) -> Set<GraphTarget>

    /// Returns the transitive resource bundle dependencies for the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func resourceBundleDependencies(path: AbsolutePath, name: String) -> Set<GraphDependencyReference>

    /// It returns true if the given target can be compiled for Mac Catalyst. To be able to compile it for Catalyst, itself and
    /// all its
    /// dependencies need to support Mac Catalyst. Otherwise it'll yield a "X not found" error.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    /// - Returns: True if a given target can be compiled for Mac Catalyst.
    func buildsForMacCatalyst(path: AbsolutePath, name: String) -> Bool

    /// Returns all non-transitive target static dependencies for the given target.
    /// - Parameters:
    ///   - path: Path to the directory where the project that defines the target is located.
    ///   - name: Name of the target.
    func directStaticDependencies(path: AbsolutePath, name: String) -> Set<GraphDependencyReference>

    /// Given a project directory and a target name, it returns an appClips dependency.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func appClipDependencies(path: AbsolutePath, name: String) -> GraphTarget?

    /// Given a project directory and a target name, it returns the list of dependencies that need to be embedded into the target
    /// product.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func embeddableFrameworks(path: AbsolutePath, name: String) -> Set<GraphDependencyReference>

    /// Given a project directory and a target name, it returns the list of dependencies that need to be linked from the target.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func linkableDependencies(path: AbsolutePath, name: String) throws -> Set<GraphDependencyReference>

    /// Given a project directory and a target name, it returns the list of dependencies that need to be added to the searchable
    /// path from the target.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func searchablePathDependencies(path: AbsolutePath, name: String) throws -> Set<GraphDependencyReference>

    /// Given a project directory and a target name, it returns a list of dependencies that need to be included in a copy files
    /// build phase
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
    func librariesSearchPaths(path: AbsolutePath, name: String) throws -> Set<AbsolutePath>

    /// Given a project directory and a target name, it returns the list of foldres with Swift modules that should be expoed to
    /// the target.
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
    func hostTargetFor(path: AbsolutePath, name: String) -> GraphTarget?

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

    /// Given a project directory and a target name, it returns all the dependencies that are ExtensionKit extensions.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func extensionKitExtensionDependencies(path: AbsolutePath, name: String) -> Set<GraphTarget>

    /// Given a project and a target name, it returns all the direct target dependencies of the target that represent Swift Macro
    /// executables.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func directSwiftMacroExecutables(path: AbsolutePath, name: String) -> Set<GraphDependencyReference>

    /// Given a project and a target name, it returns all the direct target dependencies that are a static framework representing
    /// a Swift Macro
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func directSwiftMacroFrameworkTargets(path: AbsolutePath, name: String) -> Set<GraphTarget>

    /// It returns a set containing the external dependencies that are not referenced by the projects either directly nor
    /// transitively.
    /// - Returns: The list of dependencies.
    func allOrphanExternalTargets() -> Set<GraphTarget>

    /// Returns all the non-external targets of the graph that depend on a external target.
    /// - Returns: A set containing all the targets.
    func targetsWithExternalDependencies() -> Set<GraphTarget>

    /// Returns all the targets that are part of external projects.
    /// - Returns: A set containing all the external project targets
    func allExternalTargets() -> Set<GraphTarget>

    /// External targets (e.g. from packages) might indicate that they support platforms that
    /// they don't really support. To prevent this from causing compilation issues, Tuist cascades
    /// the supported platforms down to the external dependencies.
    /// This function narrows down the platforms of the external dependencies and returns a
    /// dictionary containing the graph target as a key, and the supported platforms as the value.
    /// - Returns: A dictionary with the graph targets as keys, and the platforms that they support
    /// as values
    func externalTargetSupportedPlatforms() -> [GraphTarget: Set<Platform>]

    /// Given a target's project path and name, it returns its target dependencies that are external.
    /// - Parameters:
    ///   - path: Project path.
    ///   - name: Target name.
    /// - Returns: A set containing all the direct target dependencies that are external.
    func directTargetExternalDependencies(path: AbsolutePath, name: String) -> Set<GraphTarget>
}

extension GraphTraversing {
    public func apps() -> Set<GraphTarget> {
        targets(product: .app)
    }
}
