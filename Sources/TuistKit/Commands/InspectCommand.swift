import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

// MARK: - InspectCommand

struct InspectCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "inspect",
                             abstract: "Inspects a target from the dependency graph and prints information about it.")
    }

    // MARK: - Options

    @OptionGroup()
    var options: DocCommand.Options

    // MARK: - Run

    func run() throws {
        let absolutePath: AbsolutePath
        if let path = options.path {
            absolutePath = AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            absolutePath = FileHandler.shared.currentPath
        }
        try InspectService().run(path: absolutePath, target: options.target)
    }
}

// MARK: - Options

extension InspectCommand {
    struct Options: ParsableArguments {
        @Option(
            name: .shortAndLong,
            help: "The path to the directory from where we'll inspect the target.",
            completion: .directory
        )
        var path: String?

        @Argument(help: "The name of the target to inspect.")
        var target: String
    }
}
