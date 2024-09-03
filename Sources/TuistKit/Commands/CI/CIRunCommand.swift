import Foundation
import ArgumentParser

struct CIRunCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "run",
            abstract: "Runs a given Tuist CI workflow."
        )
    }
    
    func run() async throws {
        try await CIRunService().run()
    }
}
