import ArgumentParser
import FigSwiftArgumentParser
import Foundation
import TSCBasic

struct VersionCommand: ParsableCommand {
    
    @OptionGroup var generateFigSpec: GenerateFigSpec<Self>

    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "version",
            abstract: "Outputs the current version of tuist"
        )
    }

    func run() throws {
        try VersionService().run()
    }
}
