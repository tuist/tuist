import Basic
import Foundation
import TuistCore
import Utility

class DumpCommand: NSObject, Command {

    // MARK: - Command

    static let command = "dump"
    static let overview = "Outputs the project manifest as a JSON"

    // MARK: - Attributes

    fileprivate let fileHandler: FileHandling
    fileprivate let manifestLoader: GraphManifestLoading
    fileprivate let printer: Printing
    let pathArgument: OptionArgument<String>

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(fileHandler: FileHandler(),
                  manifestLoader: GraphManifestLoader(),
                  printer: Printer(),
                  parser: parser)
    }

    init(fileHandler: FileHandling,
         manifestLoader: GraphManifestLoading,
         printer: Printing,
         parser: ArgumentParser) {
        let subParser = parser.add(subparser: DumpCommand.command, overview: DumpCommand.overview)
        self.fileHandler = fileHandler
        self.manifestLoader = manifestLoader
        self.printer = printer
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the folder where the project manifest is",
                                     completion: .filename)
    }

    // MARK: - Command

    func run(with arguments: ArgumentParser.Result) throws {
        var path: AbsolutePath!
        if let argumentPath = arguments.get(pathArgument) {
            path = AbsolutePath(argumentPath, relativeTo: AbsolutePath.current)
        } else {
            path = AbsolutePath.current
        }
        let json: JSON = try manifestLoader.load(.project, path: path)
        printer.print(json.toString(prettyPrint: true))
    }
}
