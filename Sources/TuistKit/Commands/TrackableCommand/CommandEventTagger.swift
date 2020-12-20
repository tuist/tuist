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
    public init(analyticsTagger: TuistAnalyticsTagging = TuistAnalyticsTagger()) {
        self.analyticsTagger = analyticsTagger
    }
    
    public func tagCommand(from info: TrackableCommandInfo) {
        let commandEvent = CommandEvent(
            name: info.name,
            subcommand: info.subcommand,
            params: info.parameters,
            duration: info.duration,
            clientId: MachineEnvironment.shared.clientId ?? "unknown",
            tuistVersion: Constants.version,
            swiftVersion: MachineEnvironment.shared.swiftVersion ?? "unknown",
            macOSVersion: MachineEnvironment.shared.macOSVersion,
            machineHardwareName: MachineEnvironment.shared.hardwareName
        )
        analyticsTagger.tag(commandEvent: commandEvent)
    }
}
