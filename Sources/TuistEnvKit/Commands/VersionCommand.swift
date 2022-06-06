import ArgumentParser
import FigSwiftArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct VersionCommand: ParsableCommand {

    @OptionGroup var generateFigSpec: GenerateFigSpec<Self>

    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "envversion",
            abstract: "Outputs the current version of tuist env."
        )
    }

    func run() throws {
        try VersionService().run()
    }
}
