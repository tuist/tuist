import Foundation

/// Error type.
///
/// - abort: error thrown when an unexpected condition happens.
/// - bug: error thrown when a bug is found and the execution cannot continue.
/// - abortSilent: like abort but without printing anything to the user.
/// - bugSilent: like bug but without printing anything to the user.
public enum ErrorType {
    case abort
    case bug
    case abortSilent
    case bugSilent
}

/// An error type that decorates an error that hasn't been handled.
/// This error is reported as a bug to let us know the error hasn't been properly handled.
public struct UnhandledError: FatalError {
    /// Default initializer
    ///
    /// - Parameter error: Error that will be decorated.
    public init(error: Error) {
        self.error = error
    }

    /// The error that gets decorated.
    public let error: Error

    /// The error type. It's value is fixed to .bug so that we are aware of errors not being handled properly.
    public let type: ErrorType = .bug

    /// Error description.
    public var description: String {
        """
        We received an error that we couldn't handle:
            - Localized description: \(error.localizedDescription)
            - Error: \(error)

        If you think it's a legit issue, please file an issue including the reproducible steps: https://github.com/tuist/tuist/issues/new/choose
        """
    }
}

/// Fatal error protocol.
public protocol FatalError: Error, CustomStringConvertible {
    /// Error type.
    var type: ErrorType { get }
}
