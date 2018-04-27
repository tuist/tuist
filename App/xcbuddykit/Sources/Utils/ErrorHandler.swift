import Foundation
import Sentry

/// Error handling protocol.
protocol ErrorHandling: AnyObject {
    /// It should be called when a fatal error happens. Depending on the error it
    /// prints, and reports the error to Sentry.
    ///
    /// - Parameter error: error.
    func fatal(error: FatalError)
}

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

/// Error handler.
final class ErrorHandler: ErrorHandling {
    /// Printer.
    let printer: Printing

    /// Sentry client.
    let client: Client?

    /// Initializes the error handler with its attributes.
    ///
    /// - Parameter printer: printer.
    init(printer: Printing = Printer()) {
        if let sentryDsn = Bundle(for: ErrorHandler.self).infoDictionary?["SENTRY_DSN"] as? String {
            client = try! Client(dsn: sentryDsn)
            try! client?.startCrashHandler()
        } else {
            client = nil
        }
        self.printer = printer
    }

    /// It should be called when a fatal error happens. Depending on the error it
    /// prints, and reports the error to Sentry.
    ///
    /// - Parameter error: error.
    func fatal(error: FatalError) {
        if let description = error.description {
            printer.print(errorMessage: description)
        }
        if let bug = error.bug {
            let event = Event(level: .debug)
            event.message = bug.localizedDescription
            let semaphore = DispatchSemaphore(value: 0)
            client?.send(event: event) { _ in
                semaphore.signal()
            }
            semaphore.wait()
        }
        exit(1)
    }
}
