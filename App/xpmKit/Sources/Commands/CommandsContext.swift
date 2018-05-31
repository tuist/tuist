import Foundation

/// Utils class that contains dependencies used by commands.
protocol CommandsContexting: Contexting {
    /// Error handler.
    var errorHandler: ErrorHandling { get }
}

/// Default commands context that conforms CommandsContexting.
final class CommandsContext: Context, CommandsContexting {
    /// Error handler.
    let errorHandler: ErrorHandling

    /// Initializes the context with its attributes.
    ///
    /// - Parameter errorHandler: error handler.
    init(errorHandler: ErrorHandling = ErrorHandler()) {
        self.errorHandler = errorHandler
        super.init()
    }
}
