import Foundation
import TuistCore

/// Generator context protocol.
@available(*, deprecated, message: "The context approach for injecting dependencies is deprecated. Inject dependencies through the constructor instead.")
protocol GeneratorContexting: Contexting {
    /// Graph that is beging generated.
    var graph: Graphing { get }
}

/// Generator context.
class GeneratorContext: Context, GeneratorContexting {
    /// Graph that is being generated.
    let graph: Graphing

    /// Initializes the generator with its attributes.
    ///
    /// - Parameters:
    ///   - graph: graph that is being generated.
    ///   - printer: printer.
    ///   - fileHandler: file handler.
    ///   - shell: shell.
    ///   - resourceLocator: resource locator.
    init(graph: Graphing,
         printer: Printing = Printer(),
         fileHandler: FileHandling = FileHandler(),
         shell: Shelling = Shell(),
         resourceLocator: ResourceLocating = ResourceLocator()) {
        self.graph = graph
        super.init(fileHandler: fileHandler,
                   shell: shell,
                   printer: printer,
                   resourceLocator: resourceLocator)
    }
}
