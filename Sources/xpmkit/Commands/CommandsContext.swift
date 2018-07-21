import Foundation
import xpmcore

protocol CommandsContexting: Contexting {
    var errorHandler: ErrorHandling { get }
}

final class CommandsContext: Context, CommandsContexting {
    let errorHandler: ErrorHandling

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
