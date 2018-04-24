import Foundation

/// Command line error handling.
public protocol CommandLineErrorHandling: AnyObject {
    func run(action: () throws -> ())
}

/// Utility class that handles errors thrown from the commands.
/// It parses the errors and reports/prints them accordingly.
public class CommandLineErrorHandler: CommandLineErrorHandling {
  
    /// Error handler.
    let errorHandler: ErrorHandling
    
    /// Printer.
    let printer: Printing
    
    /// Initializes the handler with the tech logger.
    ///
    /// - Parameter errorHandler: error handler.
    public convenience init(errorHandler: ErrorHandling) {
        self.init(errorHandler: errorHandler, printer: Printer())
    }
    
    /// Initializes the handler with its attributes.
    ///
    /// - Parameters:
    ///   - errorHandler: error handler.
    ///   - printer: printer.
    init(errorHandler: ErrorHandling,
         printer: Printing = Printer()) {
        self.errorHandler = errorHandler
        self.printer = printer
    }
    
    public func run(action: () throws -> ()) {
        do {
            try action()
        } catch {
            
        }
    }
    
}
