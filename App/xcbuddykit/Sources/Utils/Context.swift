import Foundation

/// Context protocol.
protocol Contexting: AnyObject {
    /// Shell.
    var shell: Shelling { get }

    /// Util to handle files.
    var fileHandler: FileHandling { get }

    /// Printer.
    var printer: Printing { get }
    
    // InputRequerer.
    var userInputRequester: UserInputRequesting { get }

    /// Resource locator.
    var resourceLocator: ResourceLocating { get }
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
    
    /// InputRequerer.
    let userInputRequester: UserInputRequesting

    /// Resource locator.
    let resourceLocator: ResourceLocating

    /// Initializes the context with its attributess.
    ///
    /// - Parameters:
    ///   - fileHandler: file handler.
    ///   - shell: shell.
    ///   - printer: printer.
    ///   - resourceLocator: resource locator.
    init(fileHandler: FileHandling = FileHandler(),
         shell: Shelling = Shell(),
         printer: Printing = Printer(),
         userInputRequester: UserInputRequesting = UserInputRequester(),
         resourceLocator: ResourceLocating = ResourceLocator()) {
        self.fileHandler = fileHandler
        self.shell = shell
        self.printer = printer
        self.userInputRequester = userInputRequester
        self.resourceLocator = resourceLocator
    }
}
