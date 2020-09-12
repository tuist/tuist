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
                             target: options.target,
                             serve: options.mode.shouldServe,
                             port: options.port)
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

        @Flag(
            help: "Provide the documentation as md files in a temporal folder or serve it as a website."
        )
        var mode: DocCommand.Mode = .localhost

        @Option(
            name: .long,
            help: "The port to use while serving the website. Only valid for localhost mode."
        )
        var port: UInt16 = 4040

        @Argument(help: "The name of the target to generate documentation.")
        var target: String
    }
}
