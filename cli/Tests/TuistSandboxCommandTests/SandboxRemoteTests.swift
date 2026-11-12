import Foundation
import Mockable
import Testing
import TuistServer
@testable import TuistSandboxCommand

struct SandboxRemoteTests {
    private static let serverURL = URL(string: "https://sandbox-tests.tuist.dev")!
    private static let sandboxID = "a57a427c-1ffc-476f-9282-558ff3f61585"
    private static let commandID = "6a1c0d2e-3b4f-4a5b-9c6d-7e8f90a1b2c3"

    private let sandboxesService = MockSandboxesServicing()

    private var remote: SandboxRemote {
        var remote = SandboxRemote(
            accountHandle: "account",
            serverURL: Self.serverURL,
            sandboxID: Self.sandboxID,
            sandboxesService: sandboxesService
        )
        remote.sleep = { _ in }
        return remote
    }

    private static func lines(_ json: String...) throws -> AsyncThrowingStream<ServerSandboxCommandLogLine, any Error> {
        let decoded = try json.map { try JSONDecoder().decode(ServerSandboxCommandLogLine.self, from: Data($0.utf8)) }
        return AsyncThrowingStream { continuation in
            decoded.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    @Test
    func followResumesFromTheLastOffsetsAfterAFailedReadAndAnUnavailableHost() async throws {
        // The first stream ends with an `error` line, which the server sends when a read fails mid-stream.
        given(sandboxesService).streamSandboxCommandLogs(
            accountHandle: .any, serverURL: .any, sandboxID: .any, commandID: .any,
            stdoutOffset: .value(0), stderrOffset: .value(0)
        ).willReturn(try Self.lines(
            #"{"type":"stdout","data":"abc","offset":3}"#,
            #"{"type":"error","message":"No sandbox node has memory or disk left for this sandbox."}"#
        ))
        let calls = Counter()
        let resumed = try Self.lines(
            #"{"type":"stdout","data":"def","offset":6}"#,
            #"{"type":"stderr","data":"warning","offset":7}"#,
            #"{"type":"exit","status":"exited","exit_code":65}"#
        )
        given(sandboxesService).streamSandboxCommandLogs(
            accountHandle: .any, serverURL: .any, sandboxID: .any, commandID: .any,
            stdoutOffset: .value(3), stderrOffset: .value(0)
        ).willProduce { _, _, _, _, _, _ in
            if calls.increment() == 1 { throw SandboxesServiceError.unavailable("No sandbox node") }
            return resumed
        }

        var stdout = ""
        var stderr = ""
        let exit = try await remote.follow(Self.commandID) { isStandardError, data in
            if isStandardError { stderr += data } else { stdout += data }
        }

        #expect(exit == SandboxRemote.Exit(status: "exited", exitCode: 65))
        #expect(stdout == "abcdef")
        #expect(stderr == "warning")
        #expect(calls.value == 2)
    }

    @Test
    func followStopsAtOnceWhenTheCommandIsGone() async throws {
        given(sandboxesService).streamSandboxCommandLogs(
            accountHandle: .any, serverURL: .any, sandboxID: .any, commandID: .any, stdoutOffset: .any, stderrOffset: .any
        ).willThrow(SandboxesServiceError.notFound("Command not found."))

        await #expect(throws: SandboxesServiceError.notFound("Command not found.")) {
            _ = try await remote.follow(Self.commandID) { _, _ in }
        }
        verify(sandboxesService).streamSandboxCommandLogs(
            accountHandle: .any, serverURL: .any, sandboxID: .any, commandID: .any, stdoutOffset: .any, stderrOffset: .any
        ).called(1)
    }

    @Test
    func startWaitsForTheHostWhileTheServerHasNoNode() async throws {
        let calls = Counter()
        let command: ServerSandboxCommand = try JSONDecoder.iso8601.decode(
            ServerSandboxCommand.self,
            from: Data(#"""
            {"id":"\#(Self.commandID)","command":"make","stdin":false,"status":"running",
             "started_at":"2026-11-08T10:00:00Z","deadline_at":"2026-11-08T11:00:00Z"}
            """#.utf8)
        )
        given(sandboxesService).startSandboxCommand(
            accountHandle: .any, serverURL: .any, sandboxID: .any, command: .value("make"), cwd: .any,
            environment: .any, stdin: .any, timeoutMs: .any
        ).willProduce { _, _, _, _, _, _, _, _ in
            if calls.increment() <= 2 { throw SandboxesServiceError.unavailable("No sandbox node") }
            return command
        }
        let waits = Counter()
        var remote = remote
        remote.onWait = { _ in waits.increment() }

        let started = try await remote.start("make")

        #expect(started.id == Self.commandID)
        #expect(calls.value == 3)
        #expect(waits.value == 1)
    }

    @Test
    func uploadSplitsStdinAtTheServersLimitAndClosesItWithTheLastPiece() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sandbox-upload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let size = SandboxRemote.stdinChunkBytes + 10
        try Data((0 ..< size).map { UInt8($0 % 251) }).write(to: file)
        let command: ServerSandboxCommand = try JSONDecoder.iso8601.decode(
            ServerSandboxCommand.self,
            from: Data(#"""
            {"id":"\#(Self.commandID)","command":"cat","stdin":true,"status":"running",
             "started_at":"2026-11-08T10:00:00Z","deadline_at":"2026-11-08T11:00:00Z"}
            """#.utf8)
        )
        given(sandboxesService).startSandboxCommand(
            accountHandle: .any, serverURL: .any, sandboxID: .any, command: .any, cwd: .any,
            environment: .value(["TUIST_UPLOAD": "/remote/upload"]), stdin: .value(true), timeoutMs: .any
        ).willReturn(command)
        let writes = Recorder()
        given(sandboxesService).writeSandboxCommandStdin(
            accountHandle: .any, serverURL: .any, sandboxID: .any, commandID: .value(Self.commandID), data: .any, close: .any
        ).willProduce { _, _, _, _, data, close in writes.append(data, close) }
        given(sandboxesService).streamSandboxCommandLogs(
            accountHandle: .any, serverURL: .any, sandboxID: .any, commandID: .any, stdoutOffset: .any, stderrOffset: .any
        ).willReturn(try Self.lines(#"{"type":"exit","status":"exited","exit_code":0}"#))

        try await remote.upload(file, to: "/remote/upload")

        #expect(writes.entries.map(\.data.count) == [SandboxRemote.stdinChunkBytes, 10])
        #expect(writes.entries.map(\.close) == [false, true])
        #expect(Data(writes.entries.flatMap(\.data)) == (try Data(contentsOf: file)))
    }

    @Test
    func base64DecodingIsIndependentOfWhereTheStreamSplitsIt() throws {
        let encoded = Data((0 ..< 1000).map { UInt8($0 % 256) }).base64EncodedString(options: .lineLength76Characters)
        var decoder = Base64StreamDecoder()
        var decoded = Data()
        var rest = Substring(encoded)
        for size in [1, 2, 3, 5, 7, 77, 300] where !rest.isEmpty {
            decoded += try decoder.decode(String(rest.prefix(size)))
            rest = rest.dropFirst(size)
        }
        decoded += try decoder.decode(String(rest))
        decoded += try decoder.finish()

        #expect(decoded == Data((0 ..< 1000).map { UInt8($0 % 256) }))
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    @discardableResult func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(data: Data, close: Bool)] = []

    var entries: [(data: Data, close: Bool)] { lock.withLock { recorded } }

    func append(_ data: Data, _ close: Bool) {
        lock.withLock { recorded.append((data, close)) }
    }
}

extension JSONDecoder {
    fileprivate static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
