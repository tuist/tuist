import Basic
import Foundation
import TuistSupport

/// Entity responsible for providing generator models
///
/// Assumptions:
///   - TuistGenerator creates a graph of Project dependencies
///   - The projects are associated with unique paths
///   - Each path only contains one Project
///   - Whenever a dependency is encountered referencing another path,
///     this entity is consulted again to load the model at that path
public protocol GeneratorModelLoading {
    /// Load a Project model at the specified path
    ///
    /// - Parameters:
    ///   - path: The absolute path for the project model to load.
    ///   - versions: Versions of system components that Tuist interacts with.
    /// - Returns: The Project loaded from the specified path
    /// - Throws: Error encountered during the loading process (e.g. Missing project)
    func loadProject(at path: AbsolutePath, versions: Versions) throws -> Project

    /// Load a Workspace model at the specified path
    ///
    /// - Parameter path: The absolute path for the workspace model to load.
    /// - Parameter versions: Versions of system components that Tuist interacts with.
    /// - Returns: The workspace loaded from the specified path
    /// - Throws: Error encountered during the loading process (e.g. Missing workspace)
    func loadWorkspace(at path: AbsolutePath, versions: Versions) throws -> Workspace

    /// Load a Config model at the specified path
    ///
    /// - Parameter path: The absolute path for the Config model to load.
    /// - Parameter versions: Versions of system components that Tuist interacts with.
    /// - Returns: The config loaded from the specified path
    /// - Throws: Error encountered during the loading process (e.g. Missing Config file)
    func loadConfig(at path: AbsolutePath, versions: Versions) throws -> Config
}
