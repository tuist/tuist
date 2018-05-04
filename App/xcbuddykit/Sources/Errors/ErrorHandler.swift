import Foundation
import Sentry

/// Sentry client interface.
protocol SentryClienting: AnyObject {
    func startCrashHandler() throws
    func send(event: Event, completion completionHandler: SentryRequestFinished?)
}

extension Client: SentryClienting {}

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
    let client: SentryClienting?

    /// Function to finish the program execution.
    var exiter: (Int32) -> Void

    /// Initializes the error handler with the printer.
    ///
    /// - Parameter printer: printer.
    convenience init(printer: Printing = Printer()) {
        var client: SentryClienting?
        if let sentryDsn = Bundle(for: ErrorHandler.self).infoDictionary?["SENTRY_DSN"] as? String, !sentryDsn.isEmpty {
            // swiftlint:disable force_try
            client = try! Client(dsn: sentryDsn)
            // swiftlint:enable force_try
        }
        self.init(printer: printer, client: client, exiter: { exit($0) })
    }

    /// Initializes the error handler with its attributes.
    ///
    /// - Parameters:
    ///   - printer: printer.
    ///   - client: client.
    ///   - exiter:  function to finish the program execution.
    init(printer: Printing,
         client: SentryClienting?,
         exiter: @escaping (Int32) -> Void) {
        self.client = client
        // swiftlint:disable force_try
        try! client?.startCrashHandler()
        // swiftlint:enable force_try
        self.printer = printer
        self.exiter = exiter
    }

    /// It should be called when a fatal error happens. Depending on the error it
    /// prints, and reports the error to Sentry.
    ///
    /// - Parameter error: error.
    func fatal(error: FatalError) {
        if let description = error.description {
            printer.print(errorMessage: description)
        } else {
            let message = """
            An unexpected error happened. We've open an issue to fix it as soon as possible.
            We are sorry for any inconviniences it might have caused.
            """
            printer.print(errorMessage: message)
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
        exiter(1)
    }
}
