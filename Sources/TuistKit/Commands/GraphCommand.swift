import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistGenerator

/// Command that generates and exports a dot graph from the workspace or project in the current directory.
class GraphCommand: NSObject, Command {
    /// Command name.
    static var command: String = "graph"

    /// Command description.
    static var overview: String = "Generates a dot graph from the workspace or project in the current directory."

    /// File handler.
    let fileHandler: FileHandling

    /// Printer.
    let printer: Printing

    /// Dot graph generator.
    let dotGraphGenerator: DotGraphGenerating

    /// Manifest loader.
    let manifestLoader: GraphManifestLoading
    
    required convenience init(parser: ArgumentParser) {
        let fileHandler = FileHandler()
        let system = System()
        let printer = Printer()
        let resourceLocator = ResourceLocator(fileHandler: fileHandler)
        let manifestLoader = GraphManifestLoader(fileHandler: fileHandler,
                                                 system: system,
                                                 resourceLocator: resourceLocator,
                                                 deprecator: Deprecator(printer: printer))
        let manifestTargetGenerator = ManifestTargetGenerator(manifestLoader: manifestLoader,
                                                              resourceLocator: resourceLocator)
        let modelLoader = GeneratorModelLoader(fileHandler: fileHandler,
                                               manifestLoader: manifestLoader,
                                               manifestTargetGenerator: manifestTargetGenerator)

        let dotGraphGenerator = DotGraphGenerator(modelLoader: modelLoader, printer: printer, fileHandler: fileHandler)
        self.init(parser: parser,
                  fileHandler: fileHandler,
                  printer: printer,
                  dotGraphGenerator: dotGraphGenerator,
                  manifestLoader: manifestLoader)
    }

    init(parser: ArgumentParser,
         fileHandler: FileHandling,
         printer: Printing,
         dotGraphGenerator: DotGraphGenerating,
         manifestLoader: GraphManifestLoading) {
        parser.add(subparser: GraphCommand.command, overview: GraphCommand.overview)
        self.fileHandler = fileHandler
        self.printer = printer
        self.dotGraphGenerator = dotGraphGenerator
        self.manifestLoader = manifestLoader
    }

    func run(with _: ArgumentParser.Result) throws {
        let graph = try dotGraphGenerator.generate(at: fileHandler.currentPath,
                                                   manifestLoader: manifestLoader)

        let path = fileHandler.currentPath.appending(component: "graph.dot")
        if fileHandler.exists(path) {
            printer.print("Deleting existing graph at \(path.pathString)")
            try fileHandler.delete(path)
        }

        try fileHandler.write(graph, path: path, atomically: true)
        printer.print(success: "Graph exported to \(path.pathString)")
    }
}
