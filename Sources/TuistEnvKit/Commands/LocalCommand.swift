import ArgumentParser
import FigSwiftArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct LocalCommand: ParsableCommand {

    @OptionGroup var generateFigSpec: GenerateFigSpec<Self>

    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "local",
            abstract: "Creates a .tuist-version file to pin the tuist version that should be used in the current directory. If the version is not specified, it prints the local versions"
        )
    }

    @Argument(
        help: "The version that you would like to pin your current directory to"
    )
    var version: String?

    func run() throws {
        try LocalService().run(version: version)
    }
}
