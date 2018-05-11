import Foundation

/// Protocol that should be conformed by errors that can provide a printable description.
protocol ErrorStringConvertible {
    /// Error description.
    var errorDescription: String { get }
}

/// Fatal errors that can be thrown at any point of the execution.
///
/// - abort: used when something unexpected happens and the user should be alerted.
/// - bug: like abort, but it also reports the event to Sentry.
/// - abortSilent: like abort, but it doesn't print anything in the console.
/// - bugSilent: like bug, but it doesn't print anything in the console.
enum FatalError: Error, ErrorStringConvertible {
    case abort(Error & ErrorStringConvertible)
    case bug(Error & ErrorStringConvertible)
    case abortSilent(Error)
    case bugSilent(Error)

    /// Returns the error description
    var errorDescription: String {
        switch self {
        case let .abort(error):
            return error.errorDescription
        case let .bug(error):
            return error.errorDescription
        default:
            return ""
        }
    }

    /// Returns a bug to be reported.
    var bug: Error? {
        switch self {
        case let .bug(error): return error
        case let .bugSilent(error): return error
        default: return nil
        }
    }
}
