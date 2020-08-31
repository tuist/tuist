import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

// MARK: - DocCommand

struct DocCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "doc",
                             abstract: "Generates html documentation for a given target.")
    }

    // MARK: - Attributes

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

        try DocService().run(path: absolutePath, target: options.target)
    }
}

// MARK: - Options

extension DocCommand {
    struct Options: ParsableArguments {
        @Option(
            name: .shortAndLong,
            help: "The path to target sources folder",
            completion: .directory
        )
        var path: String?
        
        @Option(
            name: .shortAndLong,
            help: "The name of the target to generate documentation"
        )
        var target: String?
    }
}
