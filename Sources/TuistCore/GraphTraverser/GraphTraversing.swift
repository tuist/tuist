import Foundation
import TSCBasic

public protocol GraphTraversing {
    /// It returns the target with the given name in the project that is defined in the given directory path.
    /// - Parameters:
    ///   - path: Path to the directory that contains the definition of the project with the target is defined.
    ///   - name: Name of the target.
    func target(path: AbsolutePath, name: String) -> Target?

    /// It returns the targets of the project defined in the directory at the given path.
    /// - Parameter path: Path to the directory that contains the definition of the project.
    func targets(at path: AbsolutePath) -> [Target]

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

    /// Returns the list of test targets that depend on the one with the given name at the given path.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project definition.
    ///   - name: Name of the target whose dependant test targets will be returned.
    func testTargetsDependingOn(path: AbsolutePath, name: String) -> [Target]
}
