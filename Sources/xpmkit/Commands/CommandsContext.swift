import Foundation
import xpmcore

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
    /// - Parameters:
    ///   - errorHandler: error handler.
    ///   - fileHandler: file handler.
    ///   - shell: shell.
    ///   - printer: printer.
    ///   - resourceLocator: resource locator.
    init(errorHandler: ErrorHandling = ErrorHandler(),
         fileHandler: FileHandling = FileHandler(),
         shell: Shelling = Shell(),
         printer: Printing = Printer(),
         resourceLocator: ResourceLocating = ResourceLocator()) {
        self.errorHandler = errorHandler
        super.init(fileHandler: fileHandler,
                   shell: shell,
                   printer: printer,
                   resourceLocator: resourceLocator)
    }
}
