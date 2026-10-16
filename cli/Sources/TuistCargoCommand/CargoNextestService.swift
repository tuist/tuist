import Foundation
import TuistProcess
import TuistServer

struct CargoNextestService {
    let runner: CommandRunning

    func prepare(_ context: CargoExecutionContext, root: URL) async throws -> CargoNextestRun {
        var arguments = context.arguments
        var shardID: String?
        var shardIndex: Int?
        if let value = context.environment["TUIST_SHARD_INDEX"] {
            guard let index = Int(value),
                  index >= 0 else { throw CargoReportError(message: "TUIST_SHARD_INDEX must be a non-negative integer.") }
            shardIndex = index
            let shard = try await CargoShardService(runner: runner).prepare(
                index: index,
                directory: context.directory,
                temporary: root,
                fullHandle: context.reporting.handle,
                serverURL: context.reporting.serverURL,
                environment: context.environment
            )
            shardID = shard.id
            arguments = CargoInvocation.restrictingToModules(shard.modules, arguments: arguments)
            var options = ["--archive-file", shard.archive.path, "--workspace-remap", context.directory.pathString]
            if !arguments.contains(where: { $0 == "--no-tests" || $0.hasPrefix("--no-tests=") }) { options += [
                "--no-tests",
                "pass",
            ] }
            arguments = CargoInvocation.inserting(options, into: arguments)
        }
        let inventory = await enumerate(arguments: arguments, context: context)
        return try await configureReport(
            arguments: arguments,
            inventory: inventory,
            context: context,
            root: root,
            shardID: shardID,
            shardIndex: shardIndex
        )
    }

    private func enumerate(arguments: [String], context: CargoExecutionContext) async -> NextestInventory? {
        guard let index = CargoInvocation(arguments).commandIndex else { return nil }
        var listing = arguments
        listing[index + 1] = "list"
        guard let data = try? await context.reporting.process.capture(
            context.executable,
            arguments: CargoInvocation.inserting(["--message-format", "json"], into: Self.listArguments(listing)),
            environment: context.environment,
            directory: context.directory
        ) else { return nil }
        return try? JSONDecoder().decode(NextestInventory.self, from: Data(data.utf8))
    }

    private func configureReport(
        arguments: [String],
        inventory: NextestInventory?,
        context: CargoExecutionContext,
        root: URL,
        shardID: String?,
        shardIndex: Int?
    ) async throws -> CargoNextestRun {
        let workspace = await context.reporting.process.workspace(
            executable: context.executable,
            arguments: arguments,
            directory: context.directory,
            environment: context.environment
        )
        let reportURL = root.appendingPathComponent("junit.xml")
        let toolConfig = root.appendingPathComponent("nextest.toml")
        try "[profile.default.junit]\npath = \(CargoInvocation.quote(reportURL.path))\n".write(
            to: toolConfig,
            atomically: true,
            encoding: .utf8
        )
        let arguments = CargoInvocation.inserting(["--tool-config-file", "tuist:\(toolConfig.path)"], into: arguments)
        let target = inventory?.buildMetadata.map { URL(fileURLWithPath: $0.targetDirectory) } ?? workspace.target
        let junitURL = try NextestConfiguration.junitPath(
            workspace: workspace.root,
            target: target,
            directory: URL(fileURLWithPath: context.directory.pathString),
            arguments: arguments,
            environment: context.environment,
            fallback: reportURL
        )
        return CargoNextestRun(
            arguments: arguments,
            junitURL: junitURL,
            inventory: inventory,
            shardID: shardID,
            shardIndex: shardIndex,
            previousReport: CargoNextestRun.fingerprint(junitURL)
        )
    }

    static func listArguments(_ arguments: [String]) -> [String] {
        let valueOptions: Set<String> = [
            "--retries",
            "--test-threads",
            "-j",
            "--jobs",
            "--failure-output",
            "--success-output",
            "--status-level",
            "--final-status-level",
            "--no-tests",
            "--message-format",
            "--message-format-version",
            "--max-fail",
            "-E",
            "--filterset",
            "--partition",
        ]
        let flags: Set<String> = ["--no-fail-fast", "--fail-fast", "--no-capture", "--no-run"]
        var result: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" { break }
            if valueOptions.contains(argument) { index += 2; continue }
            if flags.contains(argument) || valueOptions
                .contains(argument.components(separatedBy: "=")[0]) ||
                (argument.hasPrefix("-j") && argument.count > 2) { index += 1; continue }
            result.append(argument)
            index += 1
        }
        return result
    }
}
