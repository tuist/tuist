import ArgumentParser
import Foundation
import TSCBasic

struct PluginArchiveCommand: ParsableCommand {
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

    func run() throws {
        try PluginArchiveService().run(
            path: path
        )
    }
}
