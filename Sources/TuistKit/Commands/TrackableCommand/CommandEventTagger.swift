import Foundation
import TuistAnalytics
import TuistSupport

public protocol CommandEventTagging {
    func tagCommand(from info: TrackableCommandInfo)
}

/// `CommandEventTagger` builds a `CommandEvent` by grouping information
/// from different sources and tells `analyticsTagger` to send the event to a provider
public final class CommandEventTagger: CommandEventTagging {
    private let analyticsTagger: TuistAnalyticsTagging
    private let machineEnvironment: MachineEnvironmentRetrieving

    public init(
        analyticsTagger: TuistAnalyticsTagging = TuistAnalyticsTagger(),
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared
    ) {
        self.analyticsTagger = analyticsTagger
        self.machineEnvironment = machineEnvironment
    }

    public func tagCommand(from info: TrackableCommandInfo) {
        let commandEvent = CommandEvent(
            name: info.name,
            subcommand: info.subcommand,
            params: info.parameters,
            duration: info.duration,
            clientId: machineEnvironment.clientId,
            tuistVersion: Constants.version,
            swiftVersion: machineEnvironment.swiftVersion,
            macOSVersion: machineEnvironment.macOSVersion,
            machineHardwareName: machineEnvironment.hardwareName
        )
        analyticsTagger.tag(commandEvent: commandEvent)
    }
}
