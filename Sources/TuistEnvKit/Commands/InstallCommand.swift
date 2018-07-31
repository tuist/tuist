import Foundation
import TuistCore
import Utility

final class InstallCommand: Command {
    
    // MARK: - Command
    
    static var command: String = "install"
    static var overview: String = "Installs a version of tuist"
    
    // MARK: - Attributes
    
    private let versionsController: VersionsControlling
    private let printer: Printing
    private let installer: Installing
    let versionArgument: PositionalArgument<String>

    // MARK: - Init
    
    convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  versionsController: VersionsController(),
                  installer: Installer(),
                  printer: Printer())
    }
    
    init(parser: ArgumentParser,
         versionsController: VersionsControlling,
         installer: Installing,
         printer: Printer) {
        parser.add(subparser: UpdateCommand.command, overview: UpdateCommand.overview)
        let subParser = parser.add(subparser: InstallCommand.command,
                                   overview: InstallCommand.overview)
        self.versionsController = versionsController
        self.printer = printer
        self.installer = installer
        versionArgument = subParser.add(positional: "version",
                                        kind: String.self,
                                        optional: false,
                                        usage: "The version of tuist to be installed")
        
    }
    
    func run(with result: ArgumentParser.Result) throws {
        let version = result.get(versionArgument)!
        let versions = versionsController.versions().map({ $0.description })
        if versions.contains(version) {
            printer.print("Version \(version) already installed, skipping")
            return
        }
        try installer.install(version: version)
    }
}
