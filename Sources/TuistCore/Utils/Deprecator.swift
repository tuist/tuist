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

final class Deprecator: Deprecating {
    /// Notifies the user about deprecations by printing a warning message.
    ///
    /// - Parameters:
    ///   - deprecation: Feature that will be deprecated.
    ///   - suggestion: Suggestions for the user to migrate.
    func notify(deprecation: String, suggestion: String) {
        let message = "\(deprecation) will be deprecated in the next major release. Use \(suggestion) instead."
        Context.shared.printer.print(deprecation: message)
    }
}
