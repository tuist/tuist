import Foundation
import Path

/// A `CommandEvent` is the analytics event to track the execution of a Tuist command
public struct CommandEvent: Codable, Equatable {
    public let runId: String
    public let name: String
    public let subcommand: String?
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
    public let graph: RunGraph?
    public let previewId: String?
    public let resultBundlePath: AbsolutePath?
    public let ranAt: Date
    public let buildRunId: String?
    public var testRunId: String?
    public let cacheEndpoint: String

    public enum Status: Codable, Equatable {
        case success, failure(String)
    }

    private enum CodingKeys: String, CodingKey {
        case runId
        case name
        case subcommand
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
        case graph
        case previewId
        case resultBundlePath
        case ranAt
        case buildRunId
        case testRunId
        case cacheEndpoint
    }

    public init(
        runId: String,
        name: String,
        subcommand: String?,
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
        graph: RunGraph?,
        previewId: String?,
        resultBundlePath: AbsolutePath?,
        ranAt: Date,
        buildRunId: String?,
        testRunId: String?,
        cacheEndpoint: String
    ) {
        self.runId = runId
        self.name = name
        self.subcommand = subcommand
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
        self.graph = graph
        self.previewId = previewId
        self.resultBundlePath = resultBundlePath
        self.ranAt = ranAt
        self.buildRunId = buildRunId
        self.testRunId = testRunId
        self.cacheEndpoint = cacheEndpoint
    }
}

#if MOCKING
    extension CommandEvent {
        public static func test(
            runId: String = "",
            name: String = "generate",
            subcommand: String? = nil,
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
            graph: RunGraph = RunGraph(name: "Graph", projects: [], binaryBuildDuration: nil),
            previewId: String? = nil,
            resultBundlePath: AbsolutePath? = nil,
            ranAt: Date = Date(),
            buildRunId: String? = nil,
            testRunId: String? = nil,
            cacheEndpoint: String = ""
        ) -> CommandEvent {
            CommandEvent(
                runId: runId,
                name: name,
                subcommand: subcommand,
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
                graph: graph,
                previewId: previewId,
                resultBundlePath: resultBundlePath,
                ranAt: ranAt,
                buildRunId: buildRunId,
                testRunId: testRunId,
                cacheEndpoint: cacheEndpoint
            )
        }
    }
#endif
