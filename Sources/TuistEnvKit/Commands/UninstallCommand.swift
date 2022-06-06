import ArgumentParser
import FigSwiftArgumentParser
import Foundation
import TuistSupport

struct UninstallCommand: ParsableCommand {

    @OptionGroup var generateFigSpec: GenerateFigSpec<Self>

    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "uninstall",
            abstract: "Uninstalls a version of tuist"
        )
    }

    @Argument(
        help: "The version of tuist to be uninstalled"
    )
    var version: String

    func run() throws {
        try UninstallService().run(version: version)
    }
}
