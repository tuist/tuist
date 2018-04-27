import Foundation

/// Utils class that contains dependencies used by commands.
protocol CommandsContexting: AnyObject {
    /// Printer used to prints messages on the console.
    var printer: Printing { get }
}

/// Default commands context that conforms CommandsContexting.
final class CommandsContext: CommandsContexting {
    /// Printer used to prints messages on the console.
    let printer: Printing

    /// Initializes the context.
    ///
    /// - Parameter printer: printer.
    init(printer: Printing = Printer()) {
        self.printer = printer
    }
}
