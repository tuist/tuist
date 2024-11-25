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
    private let swiftVersionProvider: SwiftVersionProviding

    public init(
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        gitController: GitControlling = GitController(),
        swiftVersionProvider: SwiftVersionProviding = SwiftVersionProvider.shared
    ) {
        self.machineEnvironment = machineEnvironment
        self.gitController = gitController
        self.swiftVersionProvider = swiftVersionProvider
    }

    public func make(
        from info: TrackableCommandInfo,
        path: AbsolutePath,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CommandEvent {
        var gitCommitSHA: String?
        var gitRemoteURLOrigin: String?
        var gitBranch: String?
        if gitController.isInGitRepository(workingDirectory: path) {
            if gitController.hasCurrentBranchCommits(workingDirectory: path) {
                gitCommitSHA = try gitController.currentCommitSHA(workingDirectory: path)
            }

            if try gitController.hasUrlOrigin(workingDirectory: path) {
                gitRemoteURLOrigin = try gitController.urlOrigin(workingDirectory: path)
            }

            gitBranch = try gitController.currentBranch(workingDirectory: path)
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
            swiftVersion: try swiftVersionProvider.swiftVersion(),
            macOSVersion: machineEnvironment.macOSVersion,
            machineHardwareName: machineEnvironment.hardwareName,
            isCI: machineEnvironment.isCI,
            status: info.status,
            gitCommitSHA: gitCommitSHA,
            gitRef: gitController.ref(environment: environment),
            gitRemoteURLOrigin: gitRemoteURLOrigin,
            gitBranch: gitBranch,
            targetHashes: info.targetHashes,
            graphPath: info.graphPath,
            cacheableTargets: info.cacheableTargets,
            localCacheTargetHits: info.cacheItems
                .filter { $0.source == .local && $0.cacheCategory == .binaries }
                .map(\.name),
            remoteCacheTargetHits: info.cacheItems
                .filter { $0.source == .remote && $0.cacheCategory == .binaries }
                .map(\.name),
            testTargets: info.selectiveTestsAnalytics?.testTargets ?? [],
            localTestTargetHits: info.selectiveTestsAnalytics?.localTestTargetHits ?? [],
            remoteTestTargetHits: info.selectiveTestsAnalytics?.remoteTestTargetHits ?? []
        )
        return commandEvent
    }
}
