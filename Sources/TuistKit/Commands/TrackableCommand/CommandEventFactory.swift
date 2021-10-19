import Foundation
import TuistAnalytics
import TuistAsyncQueue
import TuistSupport

/// `CommandEventTagger` builds a `CommandEvent` by grouping information
/// from different sources and tells `analyticsTagger` to send the event to a provider

public final class CommandEventFactory {
    private let machineEnvironment: MachineEnvironmentRetrieving

    public init(
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared
    ) {
        self.machineEnvironment = machineEnvironment
    }

    public func make(from info: TrackableCommandInfo) -> CommandEvent {
        let commandEvent = CommandEvent(
            name: info.name,
            subcommand: info.subcommand,
            params: info.parameters,
            durationInMs: Int(info.durationInMs),
            clientId: machineEnvironment.clientId,
            tuistVersion: Constants.version,
            swiftVersion: machineEnvironment.swiftVersion,
            macOSVersion: machineEnvironment.macOSVersion,
            machineHardwareName: machineEnvironment.hardwareName,
            isCI: machineEnvironment.isCI
        )
        return commandEvent
    }
}
