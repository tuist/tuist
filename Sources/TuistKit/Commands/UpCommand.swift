import Basic
import Foundation
import TuistCore
import Utility

/// Command that configures the environment to work on the project.
class UpCommand: NSObject, Command {
    // MARK: - Attributes

    /// Name of the command.
    static let command = "up"

    /// Description of the command.
    static let overview = "Configures the environment for the project."

    /// File handler instance to interact with the file system.
    fileprivate let fileHandler: FileHandling

    /// Printer instance to output information to the user.
    fileprivate let printer: Printing

    /// Graph loader instance to load the project and its dependencies.
    fileprivate let graphLoader: GraphLoading

    /// Graph up instance to print a warning if the environment is not configured.
    fileprivate let graphUp: GraphUpping

    // MARK: - Init

    /// Initializes the command with the CLI parser.
    ///
    /// - Parameter parser: CLI parser where the command should register itself.
    public required convenience init(parser: ArgumentParser) {
        let printer = Printer()
        let system = System()
        self.init(parser: parser,
                  fileHandler: FileHandler(),
                  printer: printer,
                  graphLoader: GraphLoader(),
                  graphUp: GraphUp(printer: printer, system: system))
    }

    /// Initializes the command with its arguments.
    ///
    /// - Parameters:
    ///   - parser: CLI parser where the command should register itself.
    ///   - fileHandler: File handler instance to interact with the file system.
    ///   - printer: Printer instance to output information to the user.
    ///   - graphLoader: Graph loader instance to load the project and its dependencies.
    ///   - graphUp: Graph up instance to print a warning if the environment is not configured.
    init(parser: ArgumentParser,
         fileHandler: FileHandling,
         printer: Printing,
         graphLoader: GraphLoading,
         graphUp: GraphUpping) {
        parser.add(subparser: UpCommand.command, overview: UpCommand.overview)
        self.fileHandler = fileHandler
        self.printer = printer
        self.graphLoader = graphLoader
        self.graphUp = graphUp
    }

    /// Runs the command using the result from parsing the command line arguments.
    ///
    /// - Throws: An error if the the configuration of the environment fails.
    func run(with _: ArgumentParser.Result) throws {
        let graph = try graphLoader.load(path: fileHandler.currentPath)
        try graphUp.meet(graph: graph)
    }
}
