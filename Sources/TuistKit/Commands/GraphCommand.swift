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

    /// Dot graph generator.
    let dotGraphGenerator: DotGraphGenerating

    /// Manifest loader.
    let manifestLoader: GraphManifestLoading

    required convenience init(parser: ArgumentParser) {
        let resourceLocator = ResourceLocator()
        let manifestLoader = GraphManifestLoader(resourceLocator: resourceLocator)
        let manifestLinter = ManifestLinter()
        let modelLoader = GeneratorModelLoader(manifestLoader: manifestLoader,
                                               manifestLinter: manifestLinter)

        let dotGraphGenerator = DotGraphGenerator(modelLoader: modelLoader)
        self.init(parser: parser,
                  dotGraphGenerator: dotGraphGenerator,
                  manifestLoader: manifestLoader)
    }

    init(parser: ArgumentParser,
         dotGraphGenerator: DotGraphGenerating,
         manifestLoader: GraphManifestLoading) {
        parser.add(subparser: GraphCommand.command, overview: GraphCommand.overview)
        self.dotGraphGenerator = dotGraphGenerator
        self.manifestLoader = manifestLoader
    }

    func run(with _: ArgumentParser.Result) throws {
        let graph = try dotGraphGenerator.generate(at: FileHandler.shared.currentPath,
                                                   manifestLoader: manifestLoader)

        let path = FileHandler.shared.currentPath.appending(component: "graph.dot")
        if FileHandler.shared.exists(path) {
            Printer.shared.print("Deleting existing graph at \(path.pathString)")
            try FileHandler.shared.delete(path)
        }

        try FileHandler.shared.write(graph, path: path, atomically: true)
        Printer.shared.print(success: "Graph exported to \(path.pathString)")
    }
}
