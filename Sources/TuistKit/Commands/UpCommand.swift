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

    /// Path to the project directory.
    let pathArgument: OptionArgument<String>

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
        let subParser = parser.add(subparser: UpCommand.command, overview: UpCommand.overview)
        self.fileHandler = fileHandler
        self.printer = printer
        self.graphLoader = graphLoader
        self.graphUp = graphUp
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the directory that contains the project.",
                                     completion: .filename)
    }

    /// Runs the command using the result from parsing the command line arguments.
    ///
    /// - Throws: An error if the the configuration of the environment fails.
    func run(with arguments: ArgumentParser.Result) throws {
        let graph = try graphLoader.load(path: path(arguments: arguments))
        try graphUp.meet(graph: graph)
    }

    /// Parses the arguments and returns the path to the directory where
    /// the up command should be ran.
    ///
    /// - Parameter arguments: Result from parsing the command line arguments.
    /// - Returns: Path to be used for the up command.
    fileprivate func path(arguments: ArgumentParser.Result) -> AbsolutePath {
        if let path = arguments.get(pathArgument) {
            return AbsolutePath(path, relativeTo: fileHandler.currentPath)
        } else {
            return fileHandler.currentPath
        }
    }
}
