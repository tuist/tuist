import Foundation
import Mockable
import Path
import TuistAnalytics
import TuistAsyncQueue
import TuistCore
import TuistSupport

/// `CommandEventTagger` builds a `CommandEvent` by grouping information
/// from different sources and tells `analyticsTagger` to send the event to a provider

public final class CommandEventFactory {
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let gitController: GitControlling

    public init(
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        gitController: GitControlling = GitController()
    ) {
        self.machineEnvironment = machineEnvironment
        self.gitController = gitController
    }

    public func make(
        from info: TrackableCommandInfo,
        path: AbsolutePath,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CommandEvent {
        let gitCommitSHA: String?
        let gitRemoteURLOrigin: String?
        if gitController.isInGitRepository(workingDirectory: path),
           gitController.hasCurrentBranchCommits(workingDirectory: path)
        {
            gitCommitSHA = try gitController.currentCommitSHA(workingDirectory: path)
            gitRemoteURLOrigin = try gitController.urlOrigin(workingDirectory: path)
        } else {
            gitCommitSHA = nil
            gitRemoteURLOrigin = nil
        }
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
            gitCommitSHA: gitCommitSHA,
            gitRef: gitController.ref(environment: environment),
            gitRemoteURLOrigin: gitRemoteURLOrigin,
            targetHashes: info.targetHashes,
            graphPath: info.graphPath
        )
        return commandEvent
    }
}
