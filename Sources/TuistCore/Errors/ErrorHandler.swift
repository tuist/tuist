import Foundation

/// Objects that conform this protocol provide a way of handling fatal errors
/// that are thrown during the execution of an app.
public protocol ErrorHandling: AnyObject {
    /// When called, this method delegates the error handling
    /// to the entity that conforms this protocol.
    ///
    /// - Parameter error: Fatal error that should be handler.
    func fatal(error: FatalError, file: StaticString, line: UInt)
}

/// The default implementation of the ErrorHandling protocol
public final class ErrorHandler: ErrorHandling {
    /// Shared instance of the error handler.
    public static let shared: ErrorHandler = ErrorHandler()

    // MARK: - Attributes

    /// Printer to output information to the user.
    let printer: Printing

    /// Function to exit the execution of the program.
    var exiter: (Int32) -> Void

    // MARK: - Init

    /// Default error handler initializer.
    ///
    /// - Parameter printer: Printer to output information to the user.
    public convenience init(printer: Printing = Printer()) {
        self.init(printer: printer, exiter: { exit($0) })
    }

    /// Default error handler initializer.
    ///
    /// - Parameters:
    ///   - printer: Printer to output information to the user.
    ///   - exiter: Instance to exit the process.
    init(printer: Printing,
         exiter: @escaping (Int32) -> Void) {
        self.printer = printer
        self.exiter = exiter
    }

    // MARK: - Public

    /// When called, this method delegates the error handling
    /// to the entity that conforms this protocol.
    ///
    /// - Parameter error: Fatal error that should be handler.
    public func fatal(error: FatalError, file _: StaticString = #file, line _: UInt = #line) {
        let isSilent = error.type == .abortSilent || error.type == .bugSilent
        if !error.description.isEmpty, !isSilent {
            printer.print(errorMessage: error.description)
        } else if isSilent {
            let message = """
            An unexpected error happened. We've opened an issue to fix it as soon as possible.
            We are sorry for any inconveniences it might have caused.
            """
            printer.print(errorMessage: message)
        }

        exiter(1)
    }

    /// Returns true if the user decided to disable the analytics by setting the TUIST_ANALYTICS_DISABLED environment variable.
    ///
    /// - Returns: True if the analytics are disabled.
    func isDisabled() -> Bool {
        return ProcessInfo.processInfo.environment["TUIST_ANALYTICS_DISABLED"] != nil
    }
}
