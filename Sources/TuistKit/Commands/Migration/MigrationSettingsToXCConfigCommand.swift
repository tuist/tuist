import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

public struct MigrationSettingsToXCConfigCommand: ParsableCommand {
    // MARK: - Configuration
    
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "settings-to-xcconfig",
            _superCommandName: "migration",
            abstract: "It extracts the build settings from a project or a target into an xcconfig file."
        )
    }
    
    // MARK: - Arguments & Flags

    @Option(
        name: [.customShort("p"), .long],
        help: "The path to the Xcode project",
        completion: .directory
    )
    var xcodeprojPath: String

    @Option(
        name: [.customShort("x"), .long],
        help: "The path to the .xcconfig file where build settings will be extracted.",
        completion: .directory
    )
    var xcconfigPath: String

    @Option(
        name: .shortAndLong,
        help: "The name of the target whose build settings will be extracted. When not passed, it extracts the build settings of the project.",
        completion: .default
    )
    var target: String?
    
    // MARK: - Init
    
    public init() {}

    // MARK: - ParsableCommand
    
    public func run() throws {
        try MigrationSettingsToXCConfigService().run(
            xcodeprojPath: xcodeprojPath,
            xcconfigPath: xcconfigPath,
            target: target
        )
    }
}
