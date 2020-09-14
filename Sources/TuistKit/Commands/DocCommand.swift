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

        try DocService().run(project: absolutePath,
                             target: options.target)
    }
}

// MARK: - Options

extension DocCommand {
    enum Mode: EnumerableFlag {
        case localhost
        case filesOnly

        static func name(for value: DocCommand.Mode) -> NameSpecification {
            switch value {
            case .localhost:
                return [.long]
            case .filesOnly:
                return [.long]
            }
        }

        var shouldServe: Bool { self == .localhost }
    }

    struct Options: ParsableArguments {
        @Option(
            name: .shortAndLong,
            help: "The path to the Project.swift container folder.",
            completion: .directory
        )
        var path: String?

        @Argument(help: "The name of the target to generate documentation.")
        var target: String
    }
}
