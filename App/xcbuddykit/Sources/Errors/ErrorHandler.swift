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

    /// Runs the given closure reporting thrown errors as FatalError.abort
    ///
    /// - Parameter closure: closure to be executed.
    func `try`(_ closure: () throws -> Void)
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

    /// Runs the given closure reporting thrown errors as FatalError.abort
    ///
    /// - Parameter closure: closure to be executed.
    func `try`(_ closure: () throws -> Void) {
        do {
            try closure()
        } catch {
            if let fatalError = error as? FatalError {
                fatal(error: fatalError)
            }
        }
    }

    /// It should be called when a fatal error happens. Depending on the error it
    /// prints, and reports the error to Sentry.
    ///
    /// - Parameter error: error.
    func fatal(error: FatalError) {
        let silent = error.type == .abortSilent || error.type == .bugSilent
        let bug = error.type == .bug || error.type == .bugSilent
        if !error.description.isEmpty && !silent {
            printer.print(errorMessage: error.description)
        } else if silent {
            let message = """
            An unexpected error happened. We've opened an issue to fix it as soon as possible.
            We are sorry for any inconviniences it might have caused.
            """
            printer.print(errorMessage: message)
        }
        if bug {
            let event = Event(level: .debug)
            event.message = error.description
            let semaphore = DispatchSemaphore(value: 0)
            client?.send(event: event) { _ in
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: DispatchTime.now() + 2.0)
        }
        exiter(1)
    }
}
