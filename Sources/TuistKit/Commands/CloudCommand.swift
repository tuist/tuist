import ArgumentParser
import Foundation
import TSCBasic

struct CloudCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "cloud",
                             abstract: "A set of commands for cloud-related operations", subcommands: [
                                 CloudAuthCommand.self,
                                 CloudSessionCommand.self,
                                 CloudLogoutCommand.self,
                                 CloudStartTargetBuildCommand.self,
                                 CloudFinishTargetBuildCommand.self,
                                 CloudWarmCacheCommand.self,
                                 CloudPrintHashesCommand.self
                             ])
    }
}
