import AnyCodable
import Foundation
import Path

/// A `CommandEvent` is the analytics event to track the execution of a Tuist command
public struct CommandEvent: Codable, Equatable, AsyncQueueEvent {
    public let runId: String
    public let name: String
    public let subcommand: String?
    public let params: [String: AnyCodable]
    public let commandArguments: [String]
    public let durationInMs: Int
    public let clientId: String
    public let tuistVersion: String
    public let swiftVersion: String
    public let macOSVersion: String
    public let machineHardwareName: String
    public let isCI: Bool
    public let status: Status
    public let gitCommitSHA: String?
    public let gitRef: String?
    public let gitRemoteURLOrigin: String?
    public let gitBranch: String?
    public let targetHashes: [CommandEventGraphTarget: String]?
    public let graphPath: AbsolutePath?
    public let cacheableTargets: [String]
    public let localCacheTargetHits: [String]
    public let remoteCacheTargetHits: [String]
    public let testTargets: [String]
    public let localTestTargetHits: [String]
    public let remoteTestTargetHits: [String]

    public enum Status: Codable, Equatable {
        case success, failure(String)
    }

    public let id = UUID()
    public let date = Date()
    public let dispatcherId = "TuistAnalytics"

    private enum CodingKeys: String, CodingKey {
        case runId
        case name
        case subcommand
        case params
        case commandArguments
        case durationInMs = "duration"
        case clientId
        case tuistVersion
        case swiftVersion
        case macOSVersion = "macos_version"
        case machineHardwareName
        case isCI
        case status
        case gitCommitSHA
        case gitRef
        case gitRemoteURLOrigin
        case gitBranch
        case targetHashes
        case graphPath
        case cacheableTargets
        case localCacheTargetHits
        case remoteCacheTargetHits
        case testTargets
        case localTestTargetHits
        case remoteTestTargetHits
    }

    public init(
        runId: String,
        name: String,
        subcommand: String?,
        params: [String: AnyCodable],
        commandArguments: [String],
        durationInMs: Int,
        clientId: String,
        tuistVersion: String,
        swiftVersion: String,
        macOSVersion: String,
        machineHardwareName: String,
        isCI: Bool,
        status: Status,
        gitCommitSHA: String?,
        gitRef: String?,
        gitRemoteURLOrigin: String?,
        gitBranch: String?,
        targetHashes: [CommandEventGraphTarget: String]?,
        graphPath: AbsolutePath?,
        cacheableTargets: [String],
        localCacheTargetHits: [String],
        remoteCacheTargetHits: [String],
        testTargets: [String],
        localTestTargetHits: [String],
        remoteTestTargetHits: [String]
    ) {
        self.runId = runId
        self.name = name
        self.subcommand = subcommand
        self.params = params
        self.commandArguments = commandArguments
        self.durationInMs = durationInMs
        self.clientId = clientId
        self.tuistVersion = tuistVersion
        self.swiftVersion = swiftVersion
        self.macOSVersion = macOSVersion
        self.machineHardwareName = machineHardwareName
        self.isCI = isCI
        self.status = status
        self.gitCommitSHA = gitCommitSHA
        self.gitRef = gitRef
        self.gitRemoteURLOrigin = gitRemoteURLOrigin
        self.gitBranch = gitBranch
        self.targetHashes = targetHashes
        self.graphPath = graphPath
        self.cacheableTargets = cacheableTargets
        self.localCacheTargetHits = localCacheTargetHits
        self.remoteCacheTargetHits = remoteCacheTargetHits
        self.testTargets = testTargets
        self.localTestTargetHits = localTestTargetHits
        self.remoteTestTargetHits = remoteTestTargetHits
    }
}

#if MOCKING
    extension CommandEvent {
        public static func test(
            runId: String = "",
            name: String = "generate",
            subcommand: String? = nil,
            params: [String: AnyCodable] = [:],
            commandArguments: [String] = [],
            durationInMs: Int = 20,
            clientId: String = "123",
            tuistVersion: String = "1.2.3",
            swiftVersion: String = "5.2",
            macOSVersion: String = "10.15",
            machineHardwareName: String = "arm64",
            status: Status = .success,
            gitCommitSHA: String? = "0f783ea776192241154f5c192cd143efde7443aa",
            gitRef: String? = "refs/heads/main",
            gitRemoteURLOrigin: String? = "https://github.com/tuist/tuist",
            gitBranch: String? = "main",
            targetHashes: [CommandEventGraphTarget: String]? = nil,
            graphPath: AbsolutePath? = nil,
            cacheableTargets: [String] = [],
            localCacheTargetHits: [String] = [],
            remoteCacheTargetHits: [String] = [],
            testTargets: [String] = [],
            localTestTargetHits: [String] = [],
            remoteTestTargetHits: [String] = []
        ) -> CommandEvent {
            CommandEvent(
                runId: runId,
                name: name,
                subcommand: subcommand,
                params: params,
                commandArguments: commandArguments,
                durationInMs: durationInMs,
                clientId: clientId,
                tuistVersion: tuistVersion,
                swiftVersion: swiftVersion,
                macOSVersion: macOSVersion,
                machineHardwareName: machineHardwareName,
                isCI: false,
                status: status,
                gitCommitSHA: gitCommitSHA,
                gitRef: gitRef,
                gitRemoteURLOrigin: gitRemoteURLOrigin,
                gitBranch: gitBranch,
                targetHashes: targetHashes,
                graphPath: graphPath,
                cacheableTargets: cacheableTargets,
                localCacheTargetHits: localCacheTargetHits,
                remoteCacheTargetHits: remoteCacheTargetHits,
                testTargets: testTargets,
                localTestTargetHits: localTestTargetHits,
                remoteTestTargetHits: remoteTestTargetHits
            )
        }
    }
#endif
