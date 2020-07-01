import ArgumentParser
import Foundation

struct CleanCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "clean",
                             abstract: "Clean all the artefacts stored locally")
    }

    func run() throws {
        try CleanService().run()
    }
}
