import ArgumentParser
import Foundation
import TSCBasic

struct CloudFinishTargetBuildCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "finish-target-build",
                             abstract: "This command tracks when a target's build finishes. This command should be executed from a build phase.")
    }

    func run() throws {
        logger.notice("Build finished")
    }
}
