import AnyCodable
import ArgumentParser
import Foundation
import Path
import TuistCore
import TuistLoader
import TuistSupport

public struct LintCommand: AsyncParsableCommand {
    public init() {}

    public var runId = UUID().uuidString

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "lint",
            subcommands: [ImplicitImportsLintCommand.self]
        )
    }
}
