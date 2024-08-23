import Foundation
import TuistAnalytics
import TuistAsyncQueue
import TuistCore
import TuistSupport

/// `CommandEventTagger` builds a `CommandEvent` by grouping information
/// from different sources and tells `analyticsTagger` to send the event to a provider

public final class CommandEventFactory {
    private let environment: Environmenting
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let gitHandler: GitHandling
    private let gitRefReader: GitRefReading

    public init(
        environment: Environmenting = Environment.shared,
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        gitHandler: GitHandling = GitHandler(),
        gitRefReader: GitRefReading = GitRefReader()
    ) {
        self.environment = environment
        self.machineEnvironment = machineEnvironment
        self.gitHandler = gitHandler
        self.gitRefReader = gitRefReader
    }

    public func make(from info: TrackableCommandInfo) throws -> CommandEvent {
        let commitSHA = try? gitHandler.currentCommitSHA()
        let gitRemoteURLOrigin = try? gitHandler.urlOrigin()
        let commandEvent = CommandEvent(
            runId: info.runId,
            name: info.name,
            subcommand: info.subcommand,
            params: info.parameters,
            commandArguments: info.commandArguments,
            durationInMs: Int(info.durationInMs),
            clientId: machineEnvironment.clientId,
            tuistVersion: Constants.version,
            swiftVersion: machineEnvironment.swiftVersion,
            macOSVersion: machineEnvironment.macOSVersion,
            machineHardwareName: machineEnvironment.hardwareName,
            isCI: machineEnvironment.isCI,
            status: info.status,
            commitSHA: commitSHA,
            gitRef: gitRefReader.read(),
            gitRemoteURLOrigin: gitRemoteURLOrigin
        )
        return commandEvent
    }
}
