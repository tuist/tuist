import ArgumentParser
import Foundation
import Path

struct PluginArchiveCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "archive",
            abstract: "Archives a plugin into a NameOfPlugin.tuist-plugin.zip."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the definition of the plugin.",
        completion: .directory,
        envKey: .pluginArchivePath
    )
    var path: String?

    func run() async throws {
        try await PluginArchiveService().run(
            path: path
        )
    }
}
