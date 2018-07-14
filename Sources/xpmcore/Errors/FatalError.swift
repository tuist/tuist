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

/// Unhandled error.
public struct UnhandledError: FatalError {
    public init(error: Error) {
        self.error = error
    }

    public let error: Error
    public var type: ErrorType { return .bugSilent }
    public var description: String { return error.localizedDescription }
}

/// Fatal error protocol.
public protocol FatalError: Error, CustomStringConvertible {
    /// Error type.
    var type: ErrorType { get }
}
