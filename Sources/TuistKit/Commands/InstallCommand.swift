import ArgumentParser
import Foundation
import TSCBasic

/// A command to install the remote content the project depends on.
public struct InstallCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "install",
            abstract: "Installs any remote content (e.g. dependencies) necessary to interact with the project."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory
    )
    var path: String?

    @Flag(
        name: .shortAndLong,
        help: "Instead of simple install, update external content when available."
    )
    var update: Bool = false

    public func run() async throws {
        try await InstallService().run(
            path: path,
            update: update
        )
    }
}
