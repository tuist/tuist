import ArgumentParser

public struct RunnerVolumeCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "volume",
            abstract: "Inspect and clear persistent runner cache volumes.",
            subcommands: [
                RunnerVolumeListCommand.self, RunnerVolumeShowCommand.self,
                RunnerVolumeJobsCommand.self, RunnerVolumeAnalyticsCommand.self,
                RunnerVolumeClearCommand.self,
            ]
        )
    }
}
