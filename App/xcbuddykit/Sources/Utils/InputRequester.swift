import Foundation

/// Protocol that represents an object that can ask the user
protocol InputRequering: AnyObject {

    /// Printer.
    var printer: Printing { get }
}

class InputRequerer: InputRequering {
 
    /// Printer.
    let printer: Printing
    
    /// Initializes the input requerer with its attributess.
    ///
    /// - Parameters:
    ///   - printer: printer.
    init(printer: Printing = Printer()) {
        self.printer = printer
    }
}
