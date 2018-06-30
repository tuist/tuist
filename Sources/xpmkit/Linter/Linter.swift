import Foundation

/// Protocol that represents an object used to lint other objects.
/// In the context of xpm, it's used to lint project models and verify
/// things that cannot be verified at compilation time.
protocol Linting {
    /// Type of object that the linter lints.
    associatedtype T

    /// Lints an object thrown an error if the linting fails.
    ///
    /// - Parameter object: object to be linted.
    /// - Throws: an error if the linting fails.
    func lint(_ object: T) throws
}
