import ArgumentParser
import Foundation
import TSCBasic
import TSCUtility

public struct TuistFixtureGeneratorCommand: ParsableCommand {
    public init() {}
    
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "tuistfixturegenerator",
            abstract: "Generates large fixtures for the purposes of stress testing Tuist",
            subcommands: [
                GenerateCommand.self,
            ]
        )
    }
}


TuistFixtureGeneratorCommand.main()
