import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

// MARK: - DocCommand

struct DocCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "doc",
                             abstract: "Generates documentation for a specifc target.")
    }

    // MARK: - Attributes

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project whose documentation will be generated.",
        completion: .directory
    )
    var path: String?

    // MARK: - Run

    func run() throws {
        let absolutePath: AbsolutePath
        if let path = path {
            absolutePath = AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            absolutePath = FileHandler.shared.currentPath
        }

        try DocService().run(path: absolutePath)
    }
}
