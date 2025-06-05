import Foundation
import Mockable
import Path
import TuistAnalytics
import TuistAsyncQueue
import TuistCore
import TuistSupport
import XcodeGraph

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
        path: AbsolutePath
    ) throws -> CommandEvent {
        let gitInfo = gitController.gitInfo(workingDirectory: path)
        let gitCommitSHA = gitInfo.sha
        let gitBranch = gitInfo.branch
        let gitRef = gitInfo.ref

        var gitRemoteURLOrigin: String?
        if gitController.isInGitRepository(workingDirectory: path) {
            if try gitController.hasUrlOrigin(workingDirectory: path) {
                gitRemoteURLOrigin = try gitController.urlOrigin(workingDirectory: path)
            }
        }
        let graph = info.graph.map {
            map(
                $0,
                binaryCacheItems: info.binaryCacheItems,
                selectiveTestingCacheItems: info.selectiveTestingCacheItems
            )
        }

        let commandEvent = CommandEvent(
            runId: info.runId,
            name: info.name,
            subcommand: info.subcommand,
            commandArguments: info.commandArguments,
            durationInMs: Int(info.durationInMs),
            clientId: machineEnvironment.clientId,
            tuistVersion: Constants.version,
            swiftVersion: try SwiftVersionProvider.current.swiftVersion(),
            macOSVersion: machineEnvironment.macOSVersion,
            machineHardwareName: machineEnvironment.hardwareName,
            isCI: Environment.current.isCI,
            status: info.status,
            gitCommitSHA: gitCommitSHA,
            gitRef: gitRef,
            gitRemoteURLOrigin: gitRemoteURLOrigin,
            gitBranch: gitBranch,
            graph: graph,
            previewId: info.previewId,
            resultBundlePath: info.resultBundlePath,
            ranAt: info.ranAt
        )
        return commandEvent
    }

    private func map(
        _ graph: Graph,
        binaryCacheItems: [AbsolutePath: [String: CacheItem]],
        selectiveTestingCacheItems: [AbsolutePath: [String: CacheItem]]
    ) -> RunGraph {
        RunGraph(
            name: graph.name,
            projects: graph.projects.map { project in
                RunProject(
                    name: project.value.name,
                    path: project.value.path.relative(to: graph.path),
                    targets: project.value.targets.map { target in
                        let binaryCacheMetadata: RunCacheTargetMetadata?
                        if let cacheItem = binaryCacheItems[project.value.path]?[target.value.name] {
                            let hit: RunCacheHit = switch cacheItem.source {
                            case .miss:
                                .miss
                            case .local:
                                .local
                            case .remote:
                                .remote
                            }

                            binaryCacheMetadata = RunCacheTargetMetadata(
                                hash: cacheItem.hash,
                                hit: hit
                            )
                        } else {
                            binaryCacheMetadata = nil
                        }
                        let selectiveTestingMetadata: RunCacheTargetMetadata?
                        if let cacheItem = selectiveTestingCacheItems[project.value.path]?[target.value.name] {
                            let hit: RunCacheHit = switch cacheItem.source {
                            case .miss:
                                .miss
                            case .local:
                                .local
                            case .remote:
                                .remote
                            }

                            selectiveTestingMetadata = RunCacheTargetMetadata(
                                hash: cacheItem.hash,
                                hit: hit
                            )
                        } else {
                            selectiveTestingMetadata = nil
                        }

                        return RunTarget(
                            name: target.value.name,
                            binaryCacheMetadata: binaryCacheMetadata,
                            selectiveTestingMetadata: selectiveTestingMetadata
                        )
                    }
                    .sorted(by: { $0.name < $1.name })
                )
            }
        )
    }
}
