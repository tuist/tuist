import Foundation

/// Buildify errors.
///
/// - abort: prints the message and exits 1.
/// - bug: like abort but reporting the bug to Sentry.
/// - abortSilent: like abort but without printing anything.
/// - bugSilent: like bug but without printing anything.
enum BuildifyError: Error {
    case abort(Error)
    case bug(Error)
    case abortSilent(Error)
    case bugSilent(Error)
}
