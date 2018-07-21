import Foundation
import xpmcore

/// Context protocol.
@available(*, deprecated, message: "The context approach for injecting dependencies is deprecated. Inject dependencies through the constructor instead.")
protocol Contexting: AnyObject {
    /// Shell.
    var shell: Shelling { get }

    /// Util to handle files.
    var fileHandler: FileHandling { get }

    /// Printer.
    var printer: Printing { get }

    /// Resource locator.
    var resourceLocator: ResourceLocating { get }
}

/// xpm uses contexts as a dependency injection mechanism.
/// Contexts are initialized by the commands and passed to the different components that will use the dependencies defined in them.
@available(*, deprecated, message: "The context approach for injecting dependencies is deprecated. Inject dependencies through the constructor instead.")
class Context: Contexting {
    /// Util to handle files.
    let fileHandler: FileHandling

    /// Shell.
    let shell: Shelling

    /// Printer.
    let printer: Printing

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
         resourceLocator: ResourceLocating = ResourceLocator()) {
        self.fileHandler = fileHandler
        self.shell = shell
        self.printer = printer
        self.resourceLocator = resourceLocator
    }
}
