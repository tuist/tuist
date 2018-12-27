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
    /// Printer instance to output the warning to the users.
    private let printer: Printing

    /// Constructs a deprecator with a printer instance.
    ///
    /// - Parameter printer: Printer instance to output the warning to the users.
    public init(printer: Printing = Printer()) {
        self.printer = printer
    }

    /// Notifies the user about deprecations by printing a warning message.
    ///
    /// - Parameters:
    ///   - deprecation: Feature that will be deprecated.
    ///   - suggestion: Suggestions for the user to migrate.
    public func notify(deprecation: String, suggestion: String) {
        let message = "\(deprecation) will be deprecated in the next major release. Use \(suggestion) instead."
        printer.print(deprecation: message)
    }
}
