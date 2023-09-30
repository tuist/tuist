import ArgumentParser
import Foundation
import TSCBasic
import TSCUtility

public struct TuistBenchmarkCommand: ParsableCommand {
    public init() {}
    
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "tuistbenchmark",
            abstract: "A utility to benchmark running tuist against a set of fixtures",
            subcommands: [
                BenchmarkCommand.self,
            ]
        )
    }
}

TuistBenchmarkCommand.main()
