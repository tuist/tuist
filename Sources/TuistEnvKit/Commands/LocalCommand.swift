import Basic
import Foundation
import SPMUtility
import TuistSupport

class LocalCommand: Command {
    // MARK: - Command

    static var command: String = "local"
    // swiftlint:disable:next line_length
    static var overview: String = "Creates a .tuist-version file to pin the tuist version that should be used in the current directory. If the version is not specified, it prints the local versions"

    // MARK: - Attributes

    let versionArgument: PositionalArgument<String>
    let versionController: VersionsControlling

    // MARK: - Init

    required convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  versionController: VersionsController())
    }

    init(parser: ArgumentParser,
         versionController: VersionsControlling) {
        let subParser = parser.add(subparser: LocalCommand.command,
                                   overview: LocalCommand.overview)
        versionArgument = subParser.add(positional: "version",
                                        kind: String.self,
                                        optional: true,
                                        usage: "The version that you would like to pin your current directory to")
        self.versionController = versionController
    }

    // MARK: - Internal

    func run(with result: ArgumentParser.Result) throws {
        if let version = result.get(versionArgument) {
            try createVersionFile(version: version)
        } else {
            try printLocalVersions()
        }
    }

    // MARK: - Fileprivate

    private func printLocalVersions() throws {
        logger.notice("The following versions are available in the local environment:", metadata: .section)
        let versions = versionController.semverVersions()
        let output = versions.sorted().reversed().map { "- \($0)" }.joined(separator: "\n")
        logger.notice("\(output)")
    }

    private func createVersionFile(version: String) throws {
        let currentPath = FileHandler.shared.currentPath
        logger.notice("Generating \(Constants.versionFileName) file with version \(version)", metadata: .section)
        let tuistVersionPath = currentPath.appending(component: Constants.versionFileName)
        try "\(version)".write(to: URL(fileURLWithPath: tuistVersionPath.pathString),
                               atomically: true,
                               encoding: .utf8)
        logger.notice("File generated at path \(tuistVersionPath.pathString)", metadata: .success)
    }
}
