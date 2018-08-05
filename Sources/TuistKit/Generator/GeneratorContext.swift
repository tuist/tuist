import Foundation
import TuistCore

/// Generator context protocol.
@available(*, deprecated, message: "The context approach for injecting dependencies is deprecated. Inject dependencies through the constructor instead.")
protocol GeneratorContexting: Contexting {
    var graph: Graphing { get }
}

/// Generator context.
class GeneratorContext: Context, GeneratorContexting {

    // MARK: - Attributes

    let graph: Graphing

    // MARK: - Init

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
