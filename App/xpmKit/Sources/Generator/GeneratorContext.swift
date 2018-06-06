import Foundation

/// Generator context protocol.
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
    init(graph: Graphing,
         printer: Printing = Printer(),
         fileHandler: FileHandling = FileHandler(),
         shell: Shelling = Shell()) {
        self.graph = graph
        super.init(fileHandler: fileHandler,
                   shell: shell,
                   printer: printer)
    }
}
