import FileSystem
import FileSystemTesting
import Foundation
import Synchronization
import Testing
@testable import TuistProcess
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

@Suite struct CommandRunnerTests {
    #if os(macOS)
        @Test(arguments: ["--jobserver-auth", "--jobserver-fds"])
        func preservesCargoJobserverDescriptors(flag: String) async throws {
            let pipe = Pipe()
            defer {
                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()
            }
            let read = pipe.fileHandleForReading.fileDescriptor
            let write = pipe.fileHandleForWriting.fileDescriptor
            let probe = "test -p /dev/fd/\(read) && test -p /dev/fd/\(write)"
            let environment = ["TUIST_CARGO_SESSION": "fixture", "CARGO_MAKEFLAGS": "\(flag)=\(read),\(write)"]
            let runner = CommandRunner()
            let output = try await runner.run(
                arguments: ["/bin/sh", "-c", "\(probe) && printf kept"],
                environment: environment
            ).concatenatedString()
            #expect(output == "kept")
            try await runner.runInheritingOutput(
                arguments: ["/bin/sh", "-c", probe], environment: environment, workingDirectory: nil
            )
            try await runner.runInheritingOutput(
                arguments: ["/bin/sh", "-c", "! test -p /dev/fd/\(read) && ! test -p /dev/fd/\(write)"],
                environment: ["CARGO_MAKEFLAGS": "\(flag)=\(read),\(write)"], workingDirectory: nil
            )
        }
    #endif

    @Test func boundedOutputHandlerStreamsLargeFailuresWithoutRetainingStderr() async throws {
        let counts = Mutex((stdout: 0, stderr: 0, maximumChunk: 0))
        do {
            try await CommandRunner().runWithOutputHandler(
                arguments: [
                    "/bin/sh",
                    "-c",
                    "/bin/dd if=/dev/zero bs=65536 count=900 2>/dev/null; /bin/dd if=/dev/zero bs=65536 count=900 >&2 2>/dev/null; exit 23",
                ],
                environment: [:], workingDirectory: nil
            ) { event in
                Thread.sleep(forTimeInterval: 0.0001)
                counts.withLock { counts in
                    switch event {
                    case let .standardOutput(bytes):
                        counts.stdout += bytes.count
                        counts.maximumChunk = max(counts.maximumChunk, bytes.count)
                    case let .standardError(bytes):
                        counts.stderr += bytes.count
                        counts.maximumChunk = max(counts.maximumChunk, bytes.count)
                    }
                }
            }
            Issue.record("Expected the child failure to be preserved")
        } catch let CommandError.terminated(code, stderr, _) {
            #expect(code == 23)
            #expect(stderr.isEmpty)
        }
        let result = counts.withLock { $0 }
        #expect(result.stdout == 65536 * 900)
        #expect(result.stderr == 65536 * 900)
        #expect(result.maximumChunk <= 65536)
    }

    @Test(.timeLimit(.minutes(1))) func boundsContinuouslyWritingDescendantsAfterPrimaryExit() async throws {
        let count = Mutex(0)
        let incomplete = Mutex(false)
        let start = Date()
        try await CommandRunner().runWithOutputHandler(
            arguments: ["/bin/sh", "-c", "/usr/bin/yes x &"],
            environment: [:], workingDirectory: nil,
            onIncompleteOutput: { incomplete.withLock { $0 = true } }
        ) { event in
            if case let .standardOutput(bytes) = event { count.withLock { $0 += bytes.count } }
        }
        #expect(count.withLock { $0 } >= 8_000_000)
        #expect(incomplete.withLock { $0 })
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0, 23])
    func boundsPeriodicallyWritingDescendantsAfterPrimaryExit(code: Int) async throws {
        let output = Mutex("")
        let count = Mutex(0)
        let incomplete = Mutex(false)
        let start = Date()
        defer {
            if let pid = Int32(output.withLock { $0.trimmingCharacters(in: .whitespacesAndNewlines) }), pid > 0 {
                _ = kill(pid, SIGTERM)
            }
        }
        do {
            try await CommandRunner().runWithOutputHandler(
                arguments: [
                    "/bin/sh", "-c",
                    "(while :; do printf x >&2; /bin/sleep 0.05; done) & printf '%s\\n' \"$!\"; exit \(code)",
                ],
                environment: [:], workingDirectory: nil,
                onIncompleteOutput: { incomplete.withLock { $0 = true } }
            ) { event in
                switch event {
                case let .standardOutput(bytes): output.withLock { $0.append(String(decoding: bytes, as: UTF8.self)) }
                case let .standardError(bytes): count.withLock { $0 += bytes.count }
                }
            }
            #expect(code == 0)
        } catch let CommandError.terminated(actual, _, _) {
            #expect(actual == Int32(code))
        }
        #expect(incomplete.withLock { $0 })
        #expect(count.withLock { $0 } > 0)
        #expect(count.withLock { $0 } < 8_000_000)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test(.inTemporaryDirectory) func preservesBufferedTailWhenTheOutputHandlerIsStalled() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let marker = directory.appending(component: "handler-started")
        let output = Mutex("")
        let incomplete = Mutex(false)
        do {
            try await CommandRunner().runWithOutputHandler(
                arguments: [
                    "/bin/sh", "-c",
                    "printf begin; while ! test -e \"$1\"; do /bin/sleep 0.01; done; printf 'tail summary'; exit 23",
                    "sh", marker.pathString,
                ],
                environment: [:], workingDirectory: nil,
                onIncompleteOutput: { incomplete.withLock { $0 = true } }
            ) { event in
                if case let .standardOutput(bytes) = event {
                    output.withLock { $0.append(String(decoding: bytes, as: UTF8.self)) }
                    if !FileManager.default.fileExists(atPath: marker.pathString) {
                        #expect(FileManager.default.createFile(atPath: marker.pathString, contents: Data()))
                        Thread.sleep(forTimeInterval: 3)
                    }
                }
            }
            Issue.record("Expected the child failure")
        } catch let CommandError.terminated(code, _, _) {
            #expect(code == 23)
        }
        #expect(output.withLock { $0 } == "begintail summary")
        #expect(!incomplete.withLock { $0 })
    }

    @Test(arguments: [0, 23]) func returnsAfterChildExitWhenDescendantsKeepPipesOpen(code: Int) async throws {
        let incomplete = Mutex(false)
        let output = Mutex("")
        let start = Date()
        do {
            try await CommandRunner().runWithOutputHandler(
                arguments: ["/bin/sh", "-c", "/bin/sleep 30 & printf '%s\\n' \"$!\"; exit \(code)"],
                environment: [:], workingDirectory: nil,
                onIncompleteOutput: { incomplete.withLock { $0 = true } }
            ) { event in
                if case let .standardOutput(bytes) = event {
                    output.withLock { $0.append(String(decoding: bytes, as: UTF8.self)) }
                }
            }
            #expect(code == 0)
        } catch let CommandError.terminated(actual, _, _) {
            #expect(actual == Int32(code))
        }
        let elapsed = Date().timeIntervalSince(start)
        let pid = try #require(Int32(output.withLock { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
        try #require(pid > 0)
        _ = kill(pid, SIGTERM)
        #expect(incomplete.withLock { $0 })
        #expect(elapsed < 5)
    }

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

    @Test(.inTemporaryDirectory) func drainsBothPipesWithoutSchedulingOutputConsumptionTasks() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let marker = directory.appending(component: "finished")
        let runner = CommandRunner(processStartedHook: {
            // Force the starvation window without depending on core count or scheduler timing:
            // no output consumption task has been created, and this worker cannot suspend.
            let deadline = Date().addingTimeInterval(30)
            while !FileManager.default.fileExists(atPath: marker.pathString), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            #expect(
                FileManager.default.fileExists(atPath: marker.pathString),
                "The child filled a pipe before the cooperative pool could start its drainer."
            )
        })

        await expectCompletes {
            let events = try await runner.run(arguments: [
                "/bin/sh", "-c",
                "dd if=/dev/zero bs=65536 count=16 2>/dev/null; "
                    + "{ dd if=/dev/zero bs=65536 count=16 2>/dev/null; } >&2; "
                    + "printf done > \"$1\"",
                "sh", marker.pathString,
            ]).reduce(into: [ProcessEvent]()) { $0.append($1) }

            let stdout = events.reduce(0) { count, event in
                if case let .standardOutput(bytes) = event { return count + bytes.count }
                return count
            }
            let stderr = events.reduce(0) { count, event in
                if case let .standardError(bytes) = event { return count + bytes.count }
                return count
            }
            #expect(stdout == 1024 * 1024)
            #expect(stderr == 1024 * 1024)
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

    @Test func reportsLaunchFailuresAndReleasesProcessPermits() async throws {
        await expectCompletes {
            let runner = CommandRunner(maximumConcurrentProcesses: 1)
            for _ in 0 ..< 200 {
                await #expect(throws: (any Error).self) {
                    try await runner.run(arguments: ["/nonexistent/tuist-process-test"]).awaitCompletion()
                }
            }
            let output = try await runner.run(arguments: ["/bin/sh", "-c", "printf recovered"]).concatenatedString()
            #expect(output == "recovered")
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
        let ready = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: marker)
            try? FileManager.default.removeItem(at: ready)
        }
        let command = "trap 'printf terminated > \(marker.path)' TERM; printf ready > \(ready.path); while :; do :; done"
        let task = Task {
            try await CommandRunner().run(arguments: ["/bin/sh", "-c", command]).awaitCompletion()
        }

        // Cancelling before the shell installs its trap would kill it without writing the marker.
        for _ in 0 ..< 100 where !FileManager.default.fileExists(atPath: ready.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
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
