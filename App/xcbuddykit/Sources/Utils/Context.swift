import Foundation

/// Context protocol.
protocol Contexting: AnyObject {
    /// Shell.
    var shell: Shelling { get }

    /// Util to handle files.
    var fileHandler: FileHandling { get }

    /// Printer.
    var printer: Printing { get }
}

/// xcbuddy uses contexts as a dependency injection mechanism.
/// Contexts are initialized by the commands and passed to the different components that will use the dependencies defined in them.
class Context: Contexting {
    /// Util to handle files.
    let fileHandler: FileHandling

    /// Shell.
    let shell: Shelling

    /// Printer.
    let printer: Printing

    /// Initializes the context with its attributess.
    ///
    /// - Parameters:
    ///   - fileHandler: file handler.
    ///   - shell: shell.
    ///   - printer: printer.
    init(fileHandler: FileHandling,
         shell: Shelling,
         printer: Printing) {
        self.fileHandler = fileHandler
        self.shell = shell
        self.printer = printer
    }
}
