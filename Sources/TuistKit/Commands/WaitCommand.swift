import ArgumentParser
import Foundation
import Path
import TuistSupport

struct WaitCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "wait",
            abstract: "Wait for any Tuist background process to finish.",
            discussion: """
            This command waits for any Tuist background process to complete, such as when waiting for build insights to be uploaded on the CI.
            """
        )
    }

    func run() async throws {
        try await WaitCommandService().run()
    }
}
