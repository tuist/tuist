import Foundation

/// Protocol that defines an interface to notify the user about features being deprecated
public protocol Deprecating {
    /// Notifies the user about deprecations by printing a warning message.
    ///
    /// - Parameters:
    ///   - deprecation: Feature that will be deprecated.
    ///   - suggestion: Suggestions for the user to migrate.
    func notify(deprecation: String, suggestion: String)
}

public final class Deprecator: Deprecating {
    /// Shared instance.
    public static var shared: Deprecating = Deprecator()

    /// Notifies the user about deprecations by printing a warning message.
    ///
    /// - Parameters:
    ///   - deprecation: Feature that will be deprecated.
    ///   - suggestion: Suggestions for the user to migrate.
    public func notify(deprecation: String, suggestion: String) {
        logger.warning("\(deprecation) will be deprecated in the next major release. \(suggestion) instead.")
    }
}
