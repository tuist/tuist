import Foundation
import TSCBasic

/// Protocol that defines an interface to interact with the project.
protocol Playgrounding {
    /// Returns the list project Playgrounds in the given project directory.
    ///
    /// - Parameter path: Directory where the project is defined.
    /// - Returns: List of paths.
    func paths(path: AbsolutePath) -> [AbsolutePath]
}

final class Playgrounds: Playgrounding {
    /// Returns the list project Playgrounds in the given project directory.
    /// It enforces an implicit convention for the Playgrounds to be in the Playgrounds directory.
    ///
    /// - Parameter path: Directory where the project is defined.
    /// - Returns: List of paths.
    func paths(path: AbsolutePath) -> [AbsolutePath] {
        path.glob("Playgrounds/*.playground").sorted()
    }
}
