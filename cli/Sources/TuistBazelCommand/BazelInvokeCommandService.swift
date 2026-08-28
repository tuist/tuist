import Command
import FileSystem
import Foundation
import Path
import TuistAlert
import TuistConfigLoader
import TuistEnvironment
import TuistGit
import TuistServer
import TuistSupport

public protocol BazelInvokeCommandServicing {
    func run(arguments: [String], directory: String?) async throws
}

public struct BazelInvokeCommandService: BazelInvokeCommandServicing {
    private let commandRunner: CommandRunning
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fileSystem: FileSysteming
    private let uploader: BazelInvocationUploadService
    private let buildEventParser: BazelBuildEventParser
    private let profileParser: BazelProfileParser
    private let gitController: GitControlling

    init(
        commandRunner: CommandRunning = CommandRunner(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fileSystem: FileSysteming = FileSystem(),
        uploader: BazelInvocationUploadService = BazelInvocationUploadService(),
        buildEventParser: BazelBuildEventParser = BazelBuildEventParser(),
        profileParser: BazelProfileParser = BazelProfileParser(),
        gitController: GitControlling = GitController()
    ) {
        self.commandRunner = commandRunner
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fileSystem = fileSystem
        self.uploader = uploader
        self.buildEventParser = buildEventParser
        self.profileParser = profileParser
        self.gitController = gitController
    }

    public func run(arguments: [String], directory: String?) async throws {
        guard !arguments.isEmpty else {
            throw BazelInvokeCommandServiceError.missingBazelArguments
        }

        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        guard let fullHandle = config.fullHandle else {
            throw BazelInvokeCommandServiceError.missingFullHandle
        }

        let invocationID = UUID().uuidString
        let startedAt = Date()
        let command = bazelCommand(from: arguments)
        let requestedCommand = BazelCommandLineRedactor.requestedCommand(arguments: arguments)
        let gitInfo = try? await gitController.gitInfo(workingDirectory: directoryPath)

        try await fileSystem.runInTemporaryDirectory(prefix: "bazel-invocation") { temporaryDirectory in
            let eventFilePath = temporaryDirectory.appending(component: "events.json")
            let profileFilePath = temporaryDirectory.appending(component: "profile.json")
            let commandArguments = instrumentedArguments(
                arguments,
                invocationID: invocationID,
                eventFilePath: eventFilePath,
                profileFilePath: profileFilePath
            )
            var logs = BazelLogCollector()
            var commandError: Error?

            do {
                for try await event in commandRunner.run(arguments: commandArguments, workingDirectory: directoryPath) {
                    switch event {
                    case let .standardOutput(bytes):
                        FileHandle.standardOutput.write(Data(bytes))
                        logs.append(bytes: bytes, stream: .standardOutput)
                    case let .standardError(bytes):
                        FileHandle.standardError.write(Data(bytes))
                        logs.append(bytes: bytes, stream: .standardError)
                    }
                }
            } catch {
                commandError = error
            }

            let finishedAt = Date()
            let profileTelemetry =
                (try? await fileSystem.readFile(at: profileFilePath))
                    .flatMap { profileParser.parseTelemetry(data: $0) }

            if let eventData = try? await fileSystem.readFile(at: eventFilePath),
               let telemetry = buildEventParser.parse(
                   data: eventData,
                   invocationID: invocationID,
                   startedAt: startedAt,
                   command: command,
                   requestedCommand: requestedCommand,
                   finishedAt: finishedAt,
                   succeeded: commandError == nil,
                   gitBranch: gitInfo?.branch,
                   gitCommitSHA: gitInfo?.sha,
                   clientPlatform: clientPlatform()
               )
            {
                do {
                    try await uploader.upload(
                        invocation: telemetry.invocation,
                        criticalPath: profileTelemetry?.criticalPath,
                        buildTimeline: profileTelemetry?.buildTimeline,
                        testResults: telemetry.testResults,
                        logs: logs.entries,
                        fullHandle: fullHandle,
                        serverURL: serverURL
                    )
                } catch {
                    AlertController.current.warning(
                        .alert("Tuist could not upload Bazel invocation telemetry: \(error.localizedDescription)")
                    )
                }
            } else {
                AlertController.current.warning(
                    .alert("Tuist could not read Bazel's build event output, so this invocation was not recorded.")
                )
            }

            if logs.didTruncate {
                AlertController.current.warning(
                    .alert("Tuist recorded the first 10 MB of Bazel command output for this invocation.")
                )
            }

            if let commandError {
                throw commandError
            }
        }
    }

    private func bazelCommand(from arguments: [String]) -> String {
        bazelCommandIndex(in: arguments).map { arguments[$0] } ?? "build"
    }

    private func clientPlatform() -> String {
        #if os(macOS)
            let operatingSystem = "macos"
        #elseif os(Linux)
            let operatingSystem = "linux"
        #else
            return "unknown"
        #endif

        #if arch(arm64)
            return "\(operatingSystem)_arm64"
        #elseif arch(x86_64)
            return "\(operatingSystem)_x86_64"
        #else
            return "unknown"
        #endif
    }

    private func instrumentedArguments(
        _ arguments: [String],
        invocationID: String,
        eventFilePath: AbsolutePath,
        profileFilePath: AbsolutePath
    ) -> [String] {
        var commandArguments = arguments
        var telemetryArguments = [
            "--invocation_id=\(invocationID)",
            "--build_event_json_file=\(eventFilePath.pathString)",
        ]

        if !hasProfileArgument(commandArguments) {
            telemetryArguments.append("--profile=\(profileFilePath.pathString)")
        }

        if let commandIndex = bazelCommandIndex(in: commandArguments) {
            commandArguments.insert(contentsOf: telemetryArguments, at: commandIndex + 1)
        } else {
            commandArguments.append(contentsOf: telemetryArguments)
        }

        return ["bazel"] + commandArguments
    }

    private func hasProfileArgument(_ arguments: [String]) -> Bool {
        arguments.contains { $0 == "--profile" || $0.hasPrefix("--profile=") }
    }

    private func bazelCommandIndex(in arguments: [String]) -> Int? {
        let commands: Set<String> = [
            "analyze-profile", "aquery", "build", "canonicalize-flags", "clean", "config", "coverage", "cquery",
            "dump", "fetch", "help", "info", "mobile-install", "mod", "query", "run", "shutdown", "sync", "test",
            "version",
        ]

        return arguments.firstIndex(where: { commands.contains($0) })
            ?? arguments.firstIndex(where: { !$0.hasPrefix("-") })
    }
}

public enum BazelInvokeCommandServiceError: LocalizedError, Equatable {
    case missingBazelArguments
    case missingFullHandle

    public var errorDescription: String? {
        switch self {
        case .missingBazelArguments:
            "Pass a Bazel command, for example: tuist bazel invoke build //..."
        case .missingFullHandle:
            "The project full handle is required. Set 'project' in your tuist.toml or 'fullHandle' in your Tuist.swift."
        }
    }
}

private struct BazelLogCollector {
    private static let maximumBytes = 10 * 1024 * 1024
    private static let maximumChunkBytes = 7 * 1024

    private(set) var entries: [BazelInvocationLogChunk] = []
    private(set) var didTruncate = false
    private var remainingBytes = maximumBytes

    mutating func append(bytes: [UInt8], stream: BazelInvocationLogChunk.Stream) {
        guard remainingBytes > 0 else {
            didTruncate = true
            return
        }

        let boundedBytes = Array(bytes.prefix(remainingBytes))
        if boundedBytes.count < bytes.count {
            didTruncate = true
        }

        for start in stride(from: 0, to: boundedBytes.count, by: Self.maximumChunkBytes) {
            let end = min(start + Self.maximumChunkBytes, boundedBytes.count)
            entries.append(
                BazelInvocationLogChunk(
                    sequenceNumber: entries.count,
                    stream: stream,
                    message: String(decoding: boundedBytes[start ..< end], as: UTF8.self)
                )
            )
        }

        remainingBytes -= boundedBytes.count
    }
}
