import Basic
import Foundation
import TuistCore
import Utility

class LocalCommand: Command {

    // MARK: - Command
    
    static var command: String = "local"
    static var overview: String = "Creates a .tuist-version file to pin the tuist version that should be used in the current directory. If the version is not specified, it prints the current version."
    
    // MARK: - Attributes
    
    let versionArgument: PositionalArgument<String>
    let fileHandler: FileHandling
    let printer: Printing


    // MARK: - Init
    
    required convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  fileHandler: FileHandler(),
                  printer: Printer())
    }

    init(parser: ArgumentParser,
         fileHandler: FileHandling,
         printer: Printing) {
        let subParser = parser.add(subparser: LocalCommand.command,
                                   overview: LocalCommand.overview)
        versionArgument = subParser.add(positional: "version",
                                        kind: String.self,
                                        optional: false,
                                        usage: "The version that you would like to pin your current directory to.")
        self.fileHandler = fileHandler
        self.printer = printer
    }


    // MARK: - Internal
    
    func run(with result: ArgumentParser.Result) throws {
        let version = result.get(versionArgument)!
        let currentPath = fileHandler.currentPath
        printer.print(section: "Generating \(Constants.versionFileName) file with version \(version).")
        let tuistVersionPath = currentPath.appending(component: Constants.versionFileName)
        try "\(version)".write(to: URL(fileURLWithPath: tuistVersionPath.asString),
                               atomically: true,
                               encoding: .utf8)
        printer.print(success: "File generated at path \(tuistVersionPath.asString).")
    }
}
