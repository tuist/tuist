import ArgumentParser
import Foundation
import TSCBasic

public struct PluginArchiveCommannd: ParsableCommand {
    // MARK: - Configuration
    
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "archive",
            abstract: "Archives a plugin into a NameOfPlugin.tuist-plugin.zip."
        )
    }

    // MARK: - Arguments and Flags
    
    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the definition of the plugin.",
        completion: .directory
    )
    var path: String?
    
    // MARK: - Init
    
    public init() {}

    // MARK: - ParsableCommand
    public func run() throws {
        try PluginArchiveService().run(
            path: path
        )
    }
}
