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
    private let versionsFetcher: VersionsFetching
    let pathArgument: OptionArgument<String>

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(manifestLoader: ManifestLoader(),
                  versionsFetcher: VersionsFetcher(),
                  parser: parser)
    }

    init(manifestLoader: ManifestLoading,
         versionsFetcher: VersionsFetching,
         parser: ArgumentParser) {
        let subParser = parser.add(subparser: DumpCommand.command, overview: DumpCommand.overview)
        self.manifestLoader = manifestLoader
        self.versionsFetcher = versionsFetcher
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
        let versions = try versionsFetcher.fetch()
        let project = try manifestLoader.loadProject(at: path, versions: versions)
        let json: JSON = try project.toJSON()
        logger.notice("\(json.toString(prettyPrint: true))")
    }
}
