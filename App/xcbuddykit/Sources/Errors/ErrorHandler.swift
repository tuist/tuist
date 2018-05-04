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
        if let sentryDsn = Bundle(for: ErrorHandler.self).infoDictionary?["SENTRY_DSN"] as? String, !sentryDsn.isEmpty {
            // swiftlint:disable force_try
            client = try! Client(dsn: sentryDsn)
            try! client?.startCrashHandler()
            // swiftlint:enable force_try
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
