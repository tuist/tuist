import ArgumentParser
import Foundation
import Path
import TuistCI
import TuistConfigLoader
import TuistEnvironment
import TuistProcess
import TuistServer

struct OnceTestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "once",
        abstract: "Distribute a portable Once test plan across CI workers.",
        subcommands: [OnceTestPlanCommand.self, OnceTestRunCommand.self]
    )
}

struct OnceTestOptions: ParsableArguments {
    @Option(name: .long, help: "The Tuist project handle (account/project).")
    var project: String?

    @Option(name: .shortAndLong, help: "The Once workspace directory.", completion: .directory)
    var path: String?

    @Option(name: .long, help: "The Once executable. It must support portable test plans.")
    var executable: String = "once"

    func service() async throws -> OnceTestService {
        let directory = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await ConfigLoader().loadConfig(path: directory)
        guard let handle = project ?? config.fullHandle else {
            throw ValidationError("Pass --project account/project or configure a Tuist project handle.")
        }
        return try OnceTestService(
            directory: directory,
            executable: executable,
            fullHandle: handle,
            serverURL: ServerEnvironmentService().url(configServerURL: config.url)
        )
    }
}

struct OnceTestPlanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Upload a Once test plan and emit a CI matrix."
    )

    @OptionGroup var options: OnceTestOptions

    @Option(name: .long, help: "A unique CI execution reference. Defaults to TUIST_SHARD_REFERENCE or the CI run.")
    var reference: String?

    @Option(name: .long, help: "Select one Once test target.")
    var target: String?

    @Option(name: .long, help: "Select tests affected by this path. Repeat for multiple paths.")
    var changedPath: [String] = []

    @Option(name: .long, help: "The number of CI shards.")
    var shardTotal: Int

    mutating func validate() throws {
        guard shardTotal > 0 else { throw ValidationError("--shard-total must be positive.") }
        guard target == nil || changedPath.isEmpty else {
            throw ValidationError("--target and --changed-path are mutually exclusive.")
        }
    }

    func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let reference = reference ?? environment["TUIST_SHARD_REFERENCE"] ?? CIController().ciInfo()?.shardReference,
              !reference.isEmpty
        else {
            throw ValidationError("Pass --reference or set TUIST_SHARD_REFERENCE.")
        }
        let plan = try await options.service().plan(
            reference: reference, target: target, changedPaths: changedPath, shardTotal: shardTotal
        )
        let shards = Array(0 ..< (plan?.shard_count ?? 0))
        let output = try JSONSerialization.data(
            withJSONObject: ["shard_plan_id": plan?.id ?? "", "shards": shards],
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(output + Data("\n".utf8))
        if let path = environment["GITHUB_OUTPUT"] {
            let file = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            defer { try? file.close() }
            try file.seekToEnd()
            let matrix = String(decoding: try JSONEncoder().encode(shards), as: UTF8.self)
            try file.write(contentsOf: Data("shard-plan-id=\(plan?.id ?? "")\nshards=\(matrix)\n".utf8))
        }
    }
}

struct OnceTestRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "run", abstract: "Execute and report one assigned Once shard.")

    @OptionGroup var options: OnceTestOptions

    @Option(name: .long, help: "The exact plan UUID from the planning job. Defaults to TUIST_SHARD_PLAN_ID.")
    var shardPlanId: String?

    @Option(name: .long, help: "The zero-based CI shard index. Defaults to TUIST_SHARD_INDEX.")
    var shardIndex: Int?

    @Option(name: .long, help: "The execution attempt, increasing when this plan is rerun. Defaults to the CI attempt or 1.")
    var shardAttempt: Int?

    @Option(name: .long, help: "The maximum number of Once batches to execute concurrently on this worker.")
    var jobs: Int = 1

    func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let id = shardPlanId ?? environment["TUIST_SHARD_PLAN_ID"], UUID(uuidString: id) != nil else {
            throw ValidationError("Pass --shard-plan-id or set TUIST_SHARD_PLAN_ID to the exact plan UUID.")
        }
        guard let index = shardIndex ?? environment["TUIST_SHARD_INDEX"].flatMap(Int.init),
              (0 ... Int(UInt32.max)).contains(index)
        else {
            throw ValidationError("Pass a UInt32 --shard-index or set TUIST_SHARD_INDEX.")
        }
        let environmentAttempt = environment["TUIST_SHARD_ATTEMPT"].flatMap { Int($0) }
        let ciAttempt = CIController().ciInfo()?.attemptNumber.flatMap { Int($0) }
        let attempt = shardAttempt ?? environmentAttempt ?? ciAttempt ?? 1
        guard (1 ... Int(UInt32.max)).contains(attempt), jobs > 0 else {
            throw ValidationError("--shard-attempt must be a positive UInt32 and --jobs must be positive.")
        }
        do {
            try await options.service().run(planID: id, index: index, attempt: attempt, jobs: jobs)
        } catch let error as CommandError {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            switch error {
            case let .terminated(code, _, _): throw ExitCode(code)
            case let .signalled(signal, _): throw ExitCode(128 + signal)
            case .executableNotFound: throw error
            }
        }
    }
}
