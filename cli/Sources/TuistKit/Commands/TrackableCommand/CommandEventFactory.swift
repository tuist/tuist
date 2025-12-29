import Foundation
import Mockable
import Path
import TuistCore
import TuistGit
import TuistSupport
import XcodeGraph

/// `CommandEventTagger` builds a `CommandEvent` by grouping information
/// from different sources and tells `analyticsTagger` to send the event to a provider.
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
        let gitInfo = try gitController.gitInfo(workingDirectory: path)

        let graph = info.graph.map {
            map(
                $0,
                graphBinaryBuildDuration: info.graphBinaryBuildDuration,
                binaryCacheItems: info.binaryCacheItems,
                selectiveTestingCacheItems: info.selectiveTestingCacheItems,
                targetContentHashSubhashes: info.targetContentHashSubhashes
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
            gitCommitSHA: gitInfo.sha,
            gitRef: gitInfo.ref,
            gitRemoteURLOrigin: gitInfo.remoteURLOrigin,
            gitBranch: gitInfo.branch,
            graph: graph,
            previewId: info.previewId,
            resultBundlePath: info.resultBundlePath,
            ranAt: info.ranAt,
            buildRunId: info.buildRunId,
            testRunId: info.testRunId,
            cacheEndpoint: info.cacheEndpoint
        )
        return commandEvent
    }

    private func map(
        _ graph: Graph,
        graphBinaryBuildDuration: TimeInterval?,
        binaryCacheItems: [AbsolutePath: [String: CacheItem]],
        selectiveTestingCacheItems: [AbsolutePath: [String: CacheItem]],
        targetContentHashSubhashes: [String: TargetContentHashSubhashes]
    ) -> RunGraph {
        let graphProjects = graph.projects.map { project in
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
                            hit: hit,
                            buildDuration: cacheItem.buildDuration,
                            subhashes: targetContentHashSubhashes[cacheItem.hash]
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
                        product: target.value.product,
                        bundleId: target.value.bundleId,
                        productName: target.value.productName,
                        destinations: target.value.destinations,
                        binaryCacheMetadata: binaryCacheMetadata,
                        selectiveTestingMetadata: selectiveTestingMetadata
                    )
                }
                .sorted(by: { $0.name < $1.name })
            )
        }
        return RunGraph(
            name: graph.name,
            projects: graphProjects,
            binaryBuildDuration: graphBinaryBuildDuration
        )
    }
}
