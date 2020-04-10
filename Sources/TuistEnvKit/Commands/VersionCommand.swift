import Basic
import Foundation
import ArgumentParser

struct VersionCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "envversion",
                             abstract: "Outputs the current version of tuist env")
    }

    // MARK: - Command

    func run(with _: ArgumentParser.Result) {
        try VersionService().run()
    }
}
