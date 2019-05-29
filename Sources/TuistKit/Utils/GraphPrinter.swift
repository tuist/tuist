import Foundation
import TuistCore
import TuistGenerator

protocol GraphPrinting {
    /// Outputs the graph to the standard output.
    ///
    /// - Parameter graph: Graph to be printed.
    func print(graph: Graph)
}

/// Outputs the graph to the standard output.
class GraphPrinter: GraphPrinting {
    /// Printer.
    let printer: Printing

    /// Initializes the instance of the printer.
    ///
    /// - Parameter printer: Printer instance.
    init(printer: Printing) {
        self.printer = printer
    }

    /// Outputs the graph to the standard output.
    ///
    /// - Parameter graph: Graph to be printed.
    func print(graph _: Graph) {
        //  TODO:
    }
}
