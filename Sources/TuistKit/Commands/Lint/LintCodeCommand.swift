import ArgumentParser
import Foundation
import TSCBasic

/// A command to lint the Swift code using Swiftlint
struct LintCodeCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "code",
                             abstract: "Lints the code of your projects using Swiftlint.")
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the workspace or project whose code will be linted.",
        completion: .directory
    )
    var path: String?

    @Argument(
        help: "The target to be linted. When not specified all the targets of the graph are linted."
    )
    var target: String?

    func run() throws {
        try LintCodeService().run(path: path, targetName: target)
    }
}
