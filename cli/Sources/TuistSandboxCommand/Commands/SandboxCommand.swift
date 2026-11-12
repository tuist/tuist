import ArgumentParser

public struct SandboxCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "sandbox",
            abstract: "Manage your account's Tuist sandboxes. Requires an account administrator.",
            subcommands: [
                SandboxListCommand.self,
                SandboxShowCommand.self,
                SandboxAnalyticsCommand.self,
                SandboxCreateCommand.self,
                SandboxExecCommand.self,
                SandboxPauseCommand.self,
                SandboxResumeCommand.self,
                SandboxArchiveCommand.self,
                SandboxDeleteCommand.self,
            ]
        )
    }
}
