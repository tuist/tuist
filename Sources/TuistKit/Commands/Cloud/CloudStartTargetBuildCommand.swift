import ArgumentParser
import Foundation
import TSCBasic

struct CloudStartTargetBuildCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "start-target-build",
                             abstract: "This command tracks when a target's build starts. This command should be executed from a build phase.")
    }

    func run() throws {
        logger.notice("Build started")
    }
}
