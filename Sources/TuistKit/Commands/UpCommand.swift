import Basic
import Foundation
import SPMUtility
import TuistSupport

/// Command that configures the environment to work on the project.
class UpCommand: NSObject, Command {
    // MARK: - Attributes

    /// Name of the command.
    static let command = "up"

    /// Description of the command.
    static let overview = "Configures the environment for the project."

    /// Path to the project directory.
    let pathArgument: OptionArgument<String>

    /// Instance to load the setup manifest and perform the project setup.
    private let setupLoader: SetupLoading

    // MARK: - Init

    /// Initializes the command with the CLI parser.
    ///
    /// - Parameter parser: CLI parser where the command should register itself.
    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  setupLoader: SetupLoader())
    }

    /// Initializes the command with its arguments.
    ///
    /// - Parameters:
    ///   - parser: CLI parser where the command should register itself.
    ///   - setupLoader: Instance to load the setup manifest and perform the project setup.
    init(parser: ArgumentParser,
         setupLoader: SetupLoading) {
        let subParser = parser.add(subparser: UpCommand.command, overview: UpCommand.overview)
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the directory that contains the project.",
                                     completion: .filename)
        self.setupLoader = setupLoader
    }

    /// Runs the command using the result from parsing the command line arguments.
    ///
    /// - Throws: An error if the the configuration of the environment fails.
    func run(with arguments: ArgumentParser.Result) throws {
        try setupLoader.meet(at: path(arguments: arguments))
    }

    /// Parses the arguments and returns the path to the directory where
    /// the up command should be ran.
    ///
    /// - Parameter arguments: Result from parsing the command line arguments.
    /// - Returns: Path to be used for the up command.
    private func path(arguments: ArgumentParser.Result) -> AbsolutePath {
        guard let path = arguments.get(pathArgument) else {
            return FileHandler.shared.currentPath
        }
        return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
    }
}
