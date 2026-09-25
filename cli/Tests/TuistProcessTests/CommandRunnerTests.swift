import Foundation
import Testing
@testable import TuistProcess

@Suite struct CommandRunnerTests {
    @Test func streamsStandardOutputAndStandardError() async throws {
        await expectCompletes {
            let stream = CommandRunner().run(arguments: ["/bin/sh", "-c", "printf output; printf error >&2"])

            let events = try await stream.reduce(into: [ProcessEvent]()) { events, event in
                events.append(event)
            }

            #expect(events.contains { event in
                if case let .standardOutput(bytes) = event {
                    return bytes == Array("output".utf8)
                }
                return false
            })
            #expect(events.contains { event in
                if case let .standardError(bytes) = event {
                    return bytes == Array("error".utf8)
                }
                return false
            })
        }
    }

    @Test func finishesWhenCommandsWriteOutputAndExitImmediately() async throws {
        await expectCompletes {
            for iteration in 0 ..< 300 {
                let output = try await CommandRunner()
                    .run(arguments: ["/bin/sh", "-c", "printf 'output \(iteration)'"])
                    .concatenatedString()
                #expect(output == "output \(iteration)")
            }
        }
    }

    @Test func reportsNonzeroExitWithStandardError() async throws {
        await expectCompletes {
            let stream = CommandRunner().run(arguments: ["/bin/sh", "-c", "printf failure >&2; exit 3"])

            do {
                try await stream.awaitCompletion()
                Issue.record("Expected the command to fail.")
            } catch let error as CommandError {
                #expect(
                    error.description ==
                        "The command '/bin/sh -c printf failure >&2; exit 3' terminated with the code 3:\nfailure"
                )
            }
        }
    }

    @Test func limitsConcurrentSubprocesses() async throws {
        let runner = CommandRunner(maximumConcurrentProcesses: 2)
        let start = Date()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 4 {
                group.addTask {
                    try await runner.run(arguments: ["/bin/sh", "-c", "sleep 0.2"]).awaitCompletion()
                }
            }
            try await group.waitForAll()
        }

        #expect(Date().timeIntervalSince(start) >= 0.35)
    }

    @Test func cancellationSendsGracefulTermination() async throws {
        let marker = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let command = "trap 'printf terminated > \(marker.path)' TERM; while :; do :; done"
        let task = Task {
            try await CommandRunner().run(arguments: ["/bin/sh", "-c", command]).awaitCompletion()
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        _ = try? await task.value

        for _ in 0 ..< 20 where !FileManager.default.fileExists(atPath: marker.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func releasesProcessPermitAfterCancellation() async throws {
        let runner = CommandRunner(maximumConcurrentProcesses: 1)
        let task = Task {
            try await runner.run(arguments: ["/bin/sh", "-c", "sleep 10"]).awaitCompletion()
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        _ = try? await task.value

        let start = Date()
        try await runner.run(arguments: ["/bin/sh", "-c", "true"]).awaitCompletion()
        #expect(Date().timeIntervalSince(start) < 0.5)
    }

    /// A read that never sees the end of the output ignores cancellation, so `.timeLimit` can't end it: the run would
    /// hang instead of failing the test.
    private func expectCompletes(
        within timeout: Duration = .seconds(60),
        sourceLocation: SourceLocation = #_sourceLocation,
        _ operation: @escaping @Sendable () async throws -> Void
    ) async {
        let (results, continuation) = AsyncStream.makeStream(of: Bool.self)
        Task {
            do {
                try await operation()
            } catch {
                Issue.record(error, sourceLocation: sourceLocation)
            }
            continuation.yield(true)
        }
        Task {
            try? await Task.sleep(for: timeout)
            continuation.yield(false)
        }
        var iterator = results.makeAsyncIterator()
        let finished = await iterator.next() ?? false
        #expect(finished, "The command never reached the end of its output.", sourceLocation: sourceLocation)
    }
}
