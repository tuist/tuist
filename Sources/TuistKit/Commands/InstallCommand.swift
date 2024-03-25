import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

/// A command to install the remote content the project depends on.
public struct InstallCommand: ContextualizedAsyncParsableCommand {
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
        try await self.run(context: try TuistContext())
    }
    
    func run(context: any Context) async throws {
        try await InstallService().run(
            path: path,
            update: update
        )
    }
}
