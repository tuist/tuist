import Foundation

public protocol Contexting {
    /// Utility to output information to the user.
    var printer: Printing { get }

    /// Utility to show deprectaion alerts to the user.
    var deprecator: Deprecating { get }
}

public final class Context: Contexting {
    /// Shared context.
    public static var shared: Contexting = Context()

    /// Utility to output information to the user.
    public var printer: Printing = Printer()

    /// Utility to show deprectaion alerts to the user.
    public var deprecator: Deprecating = Deprecator()
}
