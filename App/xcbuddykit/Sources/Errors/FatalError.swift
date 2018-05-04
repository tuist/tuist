import Foundation

/// Fatal errors that can be thrown at any point of the execution.
///
/// - abort: used when something unexpected happens and the user should be alerted.
/// - bug: like abort, but it also reports the event to Sentry.
/// - abortSilent: like abort, but it doesn't print anything in the console.
/// - bugSilent: like bug, but it doesn't print anything in the console.
enum FatalError: Error {
    case abort(Error & CustomStringConvertible)
    case bug(Error & CustomStringConvertible)
    case abortSilent(Error)
    case bugSilent(Error)

    /// Returns the error description
    var description: String? {
        switch self {
        case let .abort(error):
            return error.description
        case let .bug(error):
            return error.description
        default:
            return nil
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
