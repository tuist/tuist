import Foundation

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

    /// Function to finish the program execution.
    var exiter: (Int32) -> Void

    /// Initializes the error handler with the printer.
    ///
    /// - Parameter printer: printer.
    convenience init(printer: Printing = Printer()) {
        self.init(printer: printer, exiter: { exit($0) })
    }

    /// Initializes the error handler with its attributes.
    ///
    /// - Parameters:
    ///   - printer: printer.
    ///   - exiter:  function to finish the program execution.
    init(printer: Printing,
         exiter: @escaping (Int32) -> Void) {
        self.printer = printer
        self.exiter = exiter
    }

    /// It should be called when a fatal error happens. Depending on the error it
    /// prints, and reports the error to Sentry.
    ///
    /// - Parameter error: error.
    func fatal(error: FatalError) {
        let isSilent = error.type == .abortSilent || error.type == .bugSilent
        if !error.description.isEmpty && !isSilent {
            printer.print(errorMessage: error.description)
        } else if isSilent {
            let message = """
            An unexpected error happened. We've opened an issue to fix it as soon as possible.
            We are sorry for any inconviniences it might have caused.
            """
            printer.print(errorMessage: message)
        }
        exiter(1)
    }
}
