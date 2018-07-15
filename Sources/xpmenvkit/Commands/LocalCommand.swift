import Basic
import Foundation
import Utility
import xpmcore

class LocalCommand: Command {
    /// Command name.
    static var command: String = "local"

    /// Command overview
    static var overview: String = "Creates a .xpm-version file that pins the version in the directory where the command is executed from."

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

    init(parser: ArgumentParser,
         fileHandler: FileHandling) {
        versionArgument = parser.add(positional: "version",
                                     kind: String.self,
                                     optional: false,
                                     usage: "The version that you would like to pin your current directory to.")
        self.fileHandler = fileHandler
    }

    func run(with result: ArgumentParser.Result) throws {
        let version = result.get(versionArgument)!
        let currentPath = fileHandler.currentPath
        let xpmVersionPath = currentPath.appending(component: Constants.versionFileName)
        try "\(version)".write(to: URL(fileURLWithPath: xpmVersionPath.asString),
                               atomically: true,
                               encoding: .utf8)
    }
}
