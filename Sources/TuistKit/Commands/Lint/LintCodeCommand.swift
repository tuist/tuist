import ArgumentParser
import Foundation
import TSCBasic

/// A command to lint the Swift code using Swiftlint
struct LintCodeCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "code",
                             _superCommandName: "lint",
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

    @Flag(
        help: "Fails on warnings."
    )
    var strict: Bool = false

    func run() throws {
        try LintCodeService().run(path: path, targetName: target, strict: strict)
    }
}
