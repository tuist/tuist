import Foundation
import TuistCore

/// Context protocol.
@available(*, deprecated, message: "The context approach for injecting dependencies is deprecated. Inject dependencies through the constructor instead.")
protocol Contexting: AnyObject {
    /// Util to handle files.
    var fileHandler: FileHandling { get }

    /// Printer.
    var printer: Printing { get }

    /// Resource locator.
    var resourceLocator: ResourceLocating { get }
}

/// tuist uses contexts as a dependency injection mechanism.
/// Contexts are initialized by the commands and passed to the different components that will use the dependencies defined in them.
@available(*, deprecated, message: "The context approach for injecting dependencies is deprecated. Inject dependencies through the constructor instead.")
class Context: Contexting {
    /// Util to handle files.
    let fileHandler: FileHandling

    /// Printer.
    let printer: Printing

    /// Resource locator.
    let resourceLocator: ResourceLocating

    init(fileHandler: FileHandling = FileHandler(),
         printer: Printing = Printer(),
         resourceLocator: ResourceLocating = ResourceLocator()) {
        self.fileHandler = fileHandler
        self.printer = printer
        self.resourceLocator = resourceLocator
    }
}
