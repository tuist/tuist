import Foundation

/// Generator context protocol.
protocol GeneratorContexting: AnyObject {
    /// Graph that is beging generated.
    var graph: Graphing { get }

    /// Printer.
    var printer: Printing { get }
}

/// Generator context.
class GeneratorContext: GeneratorContexting {
    /// Graph that is being generated.
    let graph: Graphing

    /// Printer.
    let printer: Printing

    /// Initializes the generator with its attributes.
    ///
    /// - Parameters:
    ///   - graph: graph that is being generated.
    ///   - printer: printer.
    init(graph: Graphing,
         printer: Printing = Printer()) {
        self.graph = graph
        self.printer = printer
    }
}
