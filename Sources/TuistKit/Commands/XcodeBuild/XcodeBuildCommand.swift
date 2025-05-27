import ArgumentParser
import Foundation
import TuistCache
import TuistCore
import TuistHasher
import TuistServer
import TuistSupport
import XcodeGraph

public struct XcodeBuildCommand: AsyncParsableCommand, TrackableParsableCommand,
    RecentPathRememberableCommand
{
    public static var cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory()
    public static var selectiveTestingGraphHasher: SelectiveTestingGraphHashing =
        EmptySelectiveTestingGraphHasher()
    public static var selectiveTestingService: SelectiveTestingServicing =
        EmptySelectiveTestingService()

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "xcodebuild",
            abstract:
            "tuist xcodebuild extends the xcodebuild CLI with server capabilities such as selective testing or analytics.",
            subcommands: [
                XcodeBuildTestCommand.self,
                XcodeBuildTestWithoutBuildingCommand.self,
                XcodeBuildBuildCommand.self,
                XcodeBuildBuildForTestingCommand.self,
                XcodeBuildArchiveCommand.self,
            ]
        )
    }

    var analyticsRequired: Bool { true }

    public init() {}
}

struct EmptySelectiveTestingGraphHasher: SelectiveTestingGraphHashing {
    func hash(graph _: Graph, additionalStrings _: [String]) async throws -> [GraphTarget: String] {
        [:]
    }
}

struct EmptySelectiveTestingService: SelectiveTestingServicing {
    func cachedTests(
        testableGraphTargets _: [GraphTarget],
        selectiveTestingHashes _: [GraphTarget: String], selectiveTestingCacheItems _: [CacheItem]
    ) async throws -> [TestIdentifier] {
        []
    }
}
