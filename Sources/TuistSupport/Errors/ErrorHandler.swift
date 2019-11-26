import Foundation

/// Objects that conform this protocol provide a way of handling fatal errors
/// that are thrown during the execution of an app.
public protocol ErrorHandling: AnyObject {
    /// When called, this method delegates the error handling
    /// to the entity that conforms this protocol.
    ///
    /// - Parameter error: Fatal error that should be handler.
    func fatal(error: FatalError)
}

/// The default implementation of the ErrorHandling protocol
public final class ErrorHandler: ErrorHandling {
    // MARK: - Attributes

    /// Function to exit the execution of the program.
    var exiter: (Int32) -> Void

    // MARK: - Init

    /// Default error handler initializer.
    public convenience init() {
        self.init(exiter: { exit($0) })
    }

    /// Default error handler initializer.
    ///
    /// - Parameters:
    ///   - exiter: Closure to exit the execution.
    init(exiter: @escaping (Int32) -> Void) {
        self.exiter = exiter
    }

    // MARK: - Public

    /// When called, this method delegates the error handling
    /// to the entity that conforms this protocol.
    ///
    /// - Parameter error: Fatal error that should be handler.
    public func fatal(error: FatalError) {
        let isSilent = error.type == .abortSilent || error.type == .bugSilent
        if !error.description.isEmpty, !isSilent {
            Printer.shared.print(errorMessage: "\(error.description)")
        } else if isSilent {
            let message = """
            An unexpected error happened. We've opened an issue to fix it as soon as possible.
            We are sorry for any inconveniences it might have caused.
            """
            Printer.shared.print(errorMessage: "\(message)")
        }
        exiter(1)
    }
}
