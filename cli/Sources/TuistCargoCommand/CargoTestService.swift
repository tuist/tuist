import Foundation
import Synchronization
import TuistProcess

private final class CargoTestOutput: Sendable {
    struct State {
        var stdout = Data()
        var stderr = Data()
        var bounded = true
    }

    let state = Mutex(State())

    func discard() {
        state.withLock { state in
            state.bounded = false
            state.stdout.removeAll()
            state.stderr.removeAll()
        }
    }

    func receive(_ event: ProcessEvent) {
        let bytes: [UInt8]
        switch event {
        case let .standardOutput(value):
            bytes = value
            FileHandle.standardOutput.write(Data(value))
        case let .standardError(value):
            bytes = value
            FileHandle.standardError.write(Data(value))
        }
        state.withLock { state in
            guard state.bounded else { return }
            guard state.stdout.count + state.stderr.count + bytes.count <= 50_000_000 else {
                state.bounded = false
                state.stdout.removeAll()
                state.stderr.removeAll()
                return
            }
            switch event {
            case .standardOutput: state.stdout.append(contentsOf: bytes)
            case .standardError: state.stderr.append(contentsOf: bytes)
            }
        }
    }
}

struct CargoTestService {
    let runner: CommandRunning

    static func observes(_ invocation: CargoInvocation, environment: [String: String]) -> Bool {
        guard ["test", "t"].contains(invocation.command ?? ""), invocation.observesBuild,
              environment["RUST_TEST_NOCAPTURE"].map({ $0 == "0" }) ?? true else { return false }
        if ["CARGO_TERM_VERBOSE", "CARGO_TERM_QUIET"].contains(where: {
            environment[$0].map { !["false", "0"].contains($0.lowercased()) } ?? false
        }) { return false }
        let unsupported: Set<String> = [
            "--no-run", "--list", "--nocapture", "--no-capture", "--show-output", "--quiet", "-q", "--verbose", "-v", "--bench",
            "--report-time",
        ]
        let arguments = invocation.arguments
        for (index, argument) in arguments.enumerated() {
            if unsupported
                .contains(argument) ||
                (argument.hasPrefix("-v") && argument.dropFirst().allSatisfy { $0 == "v" }) { return false }
            if argument.hasPrefix("--format="), argument != "--format=pretty" { return false }
            if argument == "--format", arguments.indices.contains(index + 1), arguments[index + 1] != "pretty" { return false }
            if argument.hasPrefix("--message-format") { return false }
        }
        return true
    }

    func execute(_ context: CargoExecutionContext, completed: (CargoTestReport?) -> Void) async throws {
        let output = CargoTestOutput()
        var executionError: Error?
        do {
            try await runner.runWithOutputHandler(
                arguments: ["/usr/bin/env", context.executable] + context.arguments,
                environment: context.environment, workingDirectory: context.directory,
                onIncompleteOutput: { output.discard() },
                onOutput: { output.receive($0) }
            )
        } catch let CommandError.terminated(code, _, command) {
            executionError = CommandError.terminated(code, stderr: "", command: command)
        } catch { executionError = error }
        let captured = output.state.withLock { ($0.stdout, $0.stderr, $0.bounded) }
        var report: CargoTestReport?
        if captured.2, !Task.isCancelled {
            let metadata = await context.reporting.process.packageMetadata(
                executable: context.executable, arguments: context.arguments,
                directory: context.directory, environment: context.environment
            )
            report = CargoTestReport.read(
                stdout: captured.0, stderr: captured.1, targets: metadata.map { CargoTestTarget.read(
                    $0,
                    arguments: context.arguments
                ) } ?? [],
                directory: context.directory.pathString
            )
        }
        completed(report)
        if report == nil, context.environment["TUIST_DEBUG"] == "1" {
            FileHandle.standardError
                .write(Data("Tuist Cargo reporting: no unambiguous, complete libtest report was found.\n".utf8))
        }
        if let executionError { throw executionError }
    }
}
