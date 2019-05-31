import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistGenerator

/// It traverses the project dependencies graph and outputs it to the terminal.
class GraphCommand: NSObject, Command {
    // MARK: - Static

    /// Command name that is used for the CLI.
    static let command = "graph"

    /// Command description that is shown when using help from the CLI.
    static let overview = "Traverses the project dependency graph and outputs it to the standard output."

    // MARK: - Attributes

    /// File handler instance to interact with the file system.
    private let fileHandler: FileHandling

    /// Manifest loader instance that can load project maifests from disk
    private let manifestLoader: GraphManifestLoading

    /// Instance to load the dependency graph.
    private let graphLoader: GraphLoading

    /// Instance to output the graph.
    private let graphPrinter: GraphPrinting

    // MARK: - Init

    /// Initializes the focus command with the argument parser where the command needs to register itself.
    ///
    /// - Parameter parser: Argument parser that parses the CLI arguments.
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
        let graphLoader = GraphLoader(modelLoader: modelLoader)

        self.init(parser: parser,
                  fileHandler: fileHandler,
                  manifestLoader: manifestLoader,
                  graphLoader: graphLoader,
                  graphPrinter: GraphPrinter(printer: printer))
    }

    /// Initializes the focus command with its attributes.
    ///
    /// - Parameters:
    ///   - parser: Argument parser that parses the CLI arguments.
    ///   - fileHandler: File handler instance to interact with the file system.
    ///   - manifestLoader: Manifest loader instance that can load project maifests from disk
    ///   - graphLoader: Instance to load the dependency graph.
    ///   - graphPrinter: Instance to output the graph.
    init(parser: ArgumentParser,
         fileHandler: FileHandling,
         manifestLoader: GraphManifestLoading,
         graphLoader: GraphLoading,
         graphPrinter: GraphPrinting) {
        parser.add(subparser: GraphCommand.command, overview: GraphCommand.overview)
        self.fileHandler = fileHandler
        self.manifestLoader = manifestLoader
        self.graphLoader = graphLoader
        self.graphPrinter = graphPrinter
    }

    func run(with _: ArgumentParser.Result) throws {
        let path = fileHandler.currentPath
        let manifests = manifestLoader.manifests(at: path)

        if manifests.contains(.workspace) {
            let (graph, _) = try graphLoader.loadWorkspace(path: path)
            try graphPrinter.print(graph: graph)
        } else if manifests.contains(.project) {
            let (graph, _) = try graphLoader.loadProject(path: path)
            try graphPrinter.print(graph: graph)
        } else {
            throw GraphManifestLoaderError.manifestNotFound(path)
        }
    }
}
