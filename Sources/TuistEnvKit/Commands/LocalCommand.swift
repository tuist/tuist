import Basic
import Foundation
import TuistCore
import Utility

class LocalCommand: Command {
    // MARK: - Command

    static var command: String = "local"
    // swiftlint:disable:next line_length
    static var overview: String = "Creates a .tuist-version file to pin the tuist version that should be used in the current directory. If the version is not specified, it prints the local versions"

    // MARK: - Attributes

    let versionArgument: PositionalArgument<String>
    let fileHandler: FileHandling
    let printer: Printing
    let versionController: VersionsControlling

    // MARK: - Init

    required convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  fileHandler: FileHandler(),
                  printer: Printer(),
                  versionController: VersionsController())
    }

    init(parser: ArgumentParser,
         fileHandler: FileHandling,
         printer: Printing,
         versionController: VersionsControlling) {
        let subParser = parser.add(subparser: LocalCommand.command,
                                   overview: LocalCommand.overview)
        versionArgument = subParser.add(positional: "version",
                                        kind: String.self,
                                        optional: true,
                                        usage: "The version that you would like to pin your current directory to")
        self.fileHandler = fileHandler
        self.printer = printer
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
        printer.print(section: "The following versions are available in the local environment:")
        let versions = versionController.semverVersions()
        let output = versions.sorted().reversed().map({ "- \($0)" }).joined(separator: "\n")
        printer.print(output)
    }

    private func createVersionFile(version: String) throws {
        let currentPath = fileHandler.currentPath
        printer.print(section: "Generating \(Constants.versionFileName) file with version \(version)")
        let tuistVersionPath = currentPath.appending(component: Constants.versionFileName)
        try "\(version)".write(to: URL(fileURLWithPath: tuistVersionPath.asString),
                               atomically: true,
                               encoding: .utf8)
        printer.print(success: "File generated at path \(tuistVersionPath.asString)")
    }
}
