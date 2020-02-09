import Basic
import Foundation
import SPMUtility
import TuistLoader
import TuistSupport

class DumpCommand: NSObject, Command {
    // MARK: - Command

    static let command = "dump"
    static let overview = "Outputs the project manifest as a JSON"

    // MARK: - Attributes

    private let manifestLoader: ManifestLoading
    let pathArgument: OptionArgument<String>

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(manifestLoader: ManifestLoader(),
                  parser: parser)
    }

    init(manifestLoader: ManifestLoading,
         parser: ArgumentParser) {
        let subParser = parser.add(subparser: DumpCommand.command, overview: DumpCommand.overview)
        self.manifestLoader = manifestLoader
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the folder where the project manifest is",
                                     completion: .filename)
        
        _ = subParser.add(option: "--verbose", shortName: "-v", kind: Bool.self)
    }

    // MARK: - Command

    func run(with arguments: ArgumentParser.Result) throws {
        var path: AbsolutePath!
        if let argumentPath = arguments.get(pathArgument) {
            path = AbsolutePath(argumentPath, relativeTo: AbsolutePath.current)
        } else {
            path = AbsolutePath.current
        }
        let project = try manifestLoader.loadProject(at: path)
        let json: JSON = try project.toJSON()
        logger.info("\(json.toString(prettyPrint: true))")
    }
}
