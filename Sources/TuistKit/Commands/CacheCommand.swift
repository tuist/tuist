import Basic
import Foundation
import SPMUtility
import TuistSupport

/// Command to cache frameworks as .xcframeworks and speed up your and others' build times.
class CacheCommand: NSObject, Command {
    // MARK: - Attributes

    /// Name of the command.
    static let command = "cache"

    /// Description of the command.
    static let overview = "Cache frameworks as .xcframeworks to speed up build times in generated projects"

    /// Path to the project directory.
    let pathArgument: OptionArgument<String>

    /// Cache controller.
    let cacheController: CacheControlling

    // MARK: - Init

    /// Initializes the command with the CLI parser.
    ///
    /// - Parameter parser: CLI parser where the command should register itself.
    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser, cacheController: CacheController())
    }

    public init(parser: ArgumentParser,
                cacheController: CacheControlling) {
        let subParser = parser.add(subparser: CacheCommand.command, overview: CacheCommand.overview)
        self.cacheController = cacheController
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the directory that contains the project whose frameworks will be cached.",
                                     completion: .filename)
    }

    /// Runs the command using the result from parsing the command line arguments.
    ///
    /// - Throws: An error if the the configuration of the environment fails.
    func run(with result: ArgumentParser.Result) throws {
        let path = self.path(arguments: result)
        try cacheController.cache(path: path)
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
