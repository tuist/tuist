import ArgumentParser
import Foundation
import TuistCache
import TuistCore
import TuistHasher
import TuistServer
import XcodeGraph

public struct XcodeBuildCommand: AsyncParsableCommand, TrackableParsableCommand {
    public static var cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory()
    public static var selectiveTestingGraphHasher: SelectiveTestingGraphHashing = EmptySelectiveTestingGraphHasher()
    public static var selectiveTestingService: SelectiveTestingServicing = EmptySelectiveTestingService()

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "xcodebuild",
            abstract: "tuist xcodebuild extends the xcodebuild CLI with server capabilities such as selective testing or analytics."
        )
    }

    var analyticsRequired: Bool { true }

    public init() {}

    @Argument(
        parsing: .captureForPassthrough,
        help: "xcodebuild arguments that will be passed through to the xcodebuild CLI."
    )
    public var passthroughXcodebuildArguments: [String] = []

    public func run() async throws {
        try await XcodeBuildService(
            cacheStorageFactory: Self.cacheStorageFactory,
            selectiveTestingGraphHasher: Self.selectiveTestingGraphHasher,
            selectiveTestingService: Self.selectiveTestingService
        )
        .run(
            passthroughXcodebuildArguments: passthroughXcodebuildArguments
        )
    }
}

struct EmptySelectiveTestingGraphHasher: SelectiveTestingGraphHashing {
    func hash(graph _: Graph, additionalStrings _: [String]) async throws -> [GraphTarget: String] {
        [:]
    }
}

struct EmptySelectiveTestingService: SelectiveTestingServicing {
    func cachedTests(
        scheme _: Scheme,
        graph _: Graph,
        selectiveTestingHashes _: [GraphTarget: String], selectiveTestingCacheItems _: [CacheItem]
    ) async throws -> [TestIdentifier] {
        []
    }
}
