import Basic
import Foundation
import Utility
import xpmcore

class LocalCommand: Command {
    /// Command name.
    static var command: String = "local"

    /// Command overview
    static var overview: String = "Creates a .xpm-version file to pin the xpm version that should be used in the current directory."

    /// Version argument.
    let versionArgument: PositionalArgument<String>

    /// File handler.
    let fileHandler: FileHandling

    /// Default constructor.
    ///
    /// - Parameter parser: argument parser.
    required convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  fileHandler: FileHandler())
    }

    /// Initializes the command with its attributes.
    ///
    /// - Parameters:
    ///   - parser: The argument parser used to register arguments.
    ///   - fileHandler: file handler.
    init(parser: ArgumentParser,
         fileHandler: FileHandling) {
        let subParser = parser.add(subparser: LocalCommand.command,
                                   overview: LocalCommand.overview)
        versionArgument = subParser.add(positional: "version",
                                        kind: String.self,
                                        optional: false,
                                        usage: "The version that you would like to pin your current directory to.")
        self.fileHandler = fileHandler
    }

    /// Runs the command.
    ///
    /// - Parameter result: argument parser result.
    /// - Throws: an error if the version file cannot be written.
    func run(with result: ArgumentParser.Result) throws {
        let version = result.get(versionArgument)!
        let currentPath = fileHandler.currentPath
        let xpmVersionPath = currentPath.appending(component: Constants.versionFileName)
        try "\(version)".write(to: URL(fileURLWithPath: xpmVersionPath.asString),
                               atomically: true,
                               encoding: .utf8)
    }
}
