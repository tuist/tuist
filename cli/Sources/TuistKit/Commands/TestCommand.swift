import ArgumentParser
import Foundation
import Path
import TuistCore
import TuistServer
import TuistSupport

enum TuistTestFlagError: FatalError, Equatable {
    case invalidCombination([String])

    var description: String {
        switch self {
        case let .invalidCombination(arguments):
            "The arguments \(arguments.joined(separator: ", ")) are mutually exclusive, only of them can be used."
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidCombination:
            .abort
        }
    }
}

/// Command that tests a target from the project in the current directory.
public struct TestCommand: AsyncParsableCommand, TrackableParsableCommand,
    RecentPathRememberableCommand
{
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test",
            abstract: "Tests a project",
            subcommands: [
                TestRunCommand.self,
                TestCaseCommand.self,
            ],
            defaultSubcommand: TestRunCommand.self
        )
    }

    var analyticsRequired: Bool { true }
}

extension TestIdentifier: ArgumentParser.ExpressibleByArgument {
    public init?(argument: String) {
        do {
            try self.init(string: argument)
        } catch {
            return nil
        }
    }
}
