import FileSystem
import FileSystemTesting
import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import Synchronization
import Testing
import TuistCore
import TuistEnvironment
import TuistTesting
#if canImport(TuistXCResultService)
    import TuistXCResultService
    import XCResultParser
#endif

@testable import TuistServer

struct ReportOutboxTests {
    private let serverURL = URL(string: "https://test.tuist.dev")!
    private let eventID = "0199f5a8-3c71-7a2b-9c1d-3e4f5a6b7c8d"
    private let clock = TestClock()

    @Test(
        .withMockedEnvironment(),
        .inTemporaryDirectory
    ) func writes_the_report_before_sending_it_and_removes_it_once_accepted() async throws {
        try mockEnvironment()
        let outbox = try makeOutbox()
        let server = ScriptedServer([.status(200)]) { _ in
            #expect(outbox.pendingFiles().count == 1)
        }

        _ = try await Client.$additionalMiddlewares.withValue([server]) {
            try await sendCommandEvent(outbox)
        }

        #expect(server.requests.map(\.id) == [eventID])
        #expect(server.requests.map(\.authorized) == [true])
        #expect(!outbox.hasPendingEntries())
    }

    @Test(.withMockedEnvironment(), .inTemporaryDirectory) func the_kept_entry_records_the_report() async throws {
        try mockEnvironment()
        let outbox = try makeOutbox()
        let server = ScriptedServer([.status(502)])

        await #expect(throws: (any Error).self) {
            try await Client.$additionalMiddlewares.withValue([server]) { try await sendCommandEvent(outbox) }
        }

        let file = try #require(outbox.pendingFiles().first)
        let (entry, body) = try #require(ReportOutbox.decode(Data(contentsOf: file)))
        #expect(entry == ReportOutboxEntry(
            operation: .commandEvent, id: eventID, fullHandle: "acme/app", serverURL: serverURL, createdAt: clock.now
        ))
        let payload = try JSONDecoder().decode(Operations.createCommandEvent.Input.Body.jsonPayload.self, from: body)
        #expect(payload.id == eventID)
        #expect(payload.name == "generate")
    }

    @Test(.withMockedEnvironment(), .inTemporaryDirectory, arguments: [
        ServerFailure.status(408), .status(429), .status(500), .status(502), .status(503),
        .transport(.networkConnectionLost), .transport(.timedOut),
    ])
    func replays_a_command_event_with_the_same_id_and_body(failure: ServerFailure) async throws {
        try mockEnvironment()
        let outbox = try makeOutbox()
        let server = ScriptedServer([failure.response, .status(200)])

        await #expect(throws: (any Error).self) {
            try await Client.$additionalMiddlewares.withValue([server]) { try await sendCommandEvent(outbox) }
        }
        #expect(outbox.hasPendingEntries())
        clock.advance(by: 44 * 60)
        await Client.$additionalMiddlewares.withValue([server]) { await outbox.flush() }

        let requests = server.requests
        #expect(requests.map(\.operationID) == ["createCommandEvent", "createCommandEvent"])
        #expect(requests.map(\.id) == [eventID, eventID])
        #expect(requests[0].body == requests[1].body)
        #expect(requests.map(\.authorized) == [true, true])
        #expect(!outbox.hasPendingEntries())
    }

    @Test(
        .withMockedEnvironment(),
        .inTemporaryDirectory,
        arguments: [ServerFailure.status(502), .transport(.networkConnectionLost)]
    )
    func replays_a_cargo_test_run_with_the_same_id_and_body(failure: ServerFailure) async throws {
        try mockEnvironment()
        let outbox = try makeOutbox()
        let server = ScriptedServer([failure.response, .status(200)])

        await #expect(throws: (any Error).self) {
            try await Client.$additionalMiddlewares.withValue([server]) {
                try await CargoReportService(reportOutbox: outbox).submit(
                    Data(#"{"duration":1,"is_ci":false,"test_modules":[],"ran_at":"2026-10-22T10:00:00Z"}"#.utf8),
                    fullHandle: "acme/app",
                    serverURL: serverURL,
                    kind: "tests"
                )
            }
        }
        await Client.$additionalMiddlewares.withValue([server]) { await outbox.flush() }

        let requests = server.requests
        #expect(requests.map(\.operationID) == ["createTest", "createTest"])
        let id = try #require(requests.first?.id)
        #expect(requests.map(\.id) == [id, id])
        #expect(requests[0].body == requests[1].body)
        #expect(!outbox.hasPendingEntries())
    }

    #if canImport(TuistXCResultService)
        @Test(.withMockedEnvironment(), .inTemporaryDirectory) func replays_a_test_run_with_the_same_id_and_body() async throws {
            try mockEnvironment()
            let outbox = try makeOutbox()
            let server = ScriptedServer([.status(503), .status(200)])

            await #expect(throws: (any Error).self) {
                try await Client.$additionalMiddlewares.withValue([server]) { try await createTest(outbox) }
            }
            await Client.$additionalMiddlewares.withValue([server]) { await outbox.flush() }

            let requests = server.requests
            #expect(requests.map(\.id) == [eventID, eventID])
            #expect(requests[0].body == requests[1].body)
            #expect(!outbox.hasPendingEntries())
        }

        @Test(.withMockedEnvironment(), .inTemporaryDirectory, arguments: [400, 401, 403, 404, 422])
        func drops_a_test_run_the_server_rejected(status: Int) async throws {
            try mockEnvironment()
            let outbox = try makeOutbox()
            let server = ScriptedServer([.status(status)])

            await #expect(throws: (any Error).self) {
                try await Client.$additionalMiddlewares.withValue([server]) { try await createTest(outbox) }
            }

            #expect(server.requests.count == 1)
            #expect(!outbox.hasPendingEntries())
        }

        @Test(.withMockedEnvironment(), .inTemporaryDirectory) func does_not_keep_a_credential_free_test_run() async throws {
            let environment = try #require(Environment.mocked)
            environment.variables["TUIST_HTTP_MAXIMUM_RETRY_COUNT"] = "0"
            let outbox = try makeOutbox()
            let server = ScriptedServer([.status(502)])
            let serverURL = try #require(URL(string: "https://tuist.example"))

            await withoutStoredCredentials {
                await ServerReportPublishingMode.$serverAllowsNetworkPublishing.withValue({ _ in true }) {
                    await #expect(throws: (any Error).self) {
                        try await Client.$additionalMiddlewares.withValue([server]) {
                            try await createTest(outbox, serverURL: serverURL)
                        }
                    }
                }
            }

            #expect(server.requests.map(\.authorized) == [false])
            #expect(!outbox.hasPendingEntries())
        }
    #endif

    @Test(.withMockedEnvironment(), .inTemporaryDirectory, arguments: [401, 403])
    func drops_a_command_event_the_server_rejected(status: Int) async throws {
        try mockEnvironment()
        let outbox = try makeOutbox()
        let server = ScriptedServer([.status(status)])

        await #expect(throws: (any Error).self) {
            try await Client.$additionalMiddlewares.withValue([server]) { try await sendCommandEvent(outbox) }
        }

        #expect(!outbox.hasPendingEntries())
    }

    @Test(.withMockedEnvironment(), .inTemporaryDirectory) func drops_a_replay_the_server_rejects() async throws {
        try mockEnvironment()
        let outbox = try makeOutbox()
        let server = ScriptedServer([.status(502), .status(403)])

        await #expect(throws: (any Error).self) {
            try await Client.$additionalMiddlewares.withValue([server]) { try await sendCommandEvent(outbox) }
        }
        await Client.$additionalMiddlewares.withValue([server]) { await outbox.flush() }

        #expect(server.requests.count == 2)
        #expect(!outbox.hasPendingEntries())
    }

    @Test(
        .withMockedEnvironment(),
        .inTemporaryDirectory
    ) func does_not_keep_a_command_event_sent_without_credentials() async throws {
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_HTTP_MAXIMUM_RETRY_COUNT"] = "0"
        let outbox = try makeOutbox()
        let server = ScriptedServer([.status(502)])

        await withoutStoredCredentials {
            await #expect(throws: (any Error).self) {
                try await ServerAuthenticationConfig.withOptionalAuthentication(true) {
                    try await Client.$additionalMiddlewares.withValue([server]) { try await sendCommandEvent(outbox) }
                }
            }
        }

        #expect(server.requests.map(\.authorized) == [false])
        #expect(!outbox.hasPendingEntries())
    }

    @Test(
        .withMockedEnvironment(),
        .inTemporaryDirectory
    ) func keeps_an_entry_instead_of_replaying_it_without_credentials() async throws {
        try mockEnvironment()
        let outbox = try makeOutbox()
        let server = ScriptedServer([.status(502)])
        await #expect(throws: (any Error).self) {
            try await Client.$additionalMiddlewares.withValue([server]) { try await sendCommandEvent(outbox) }
        }
        try #require(Environment.mocked).variables["TUIST_TOKEN"] = nil

        await withoutStoredCredentials {
            await ServerAuthenticationConfig.$current.withValue(.init(optionalAuthentication: true)) {
                await Client.$additionalMiddlewares.withValue([server]) { await outbox.flush() }
            }
        }

        #expect(server.requests.count == 1)
        #expect(outbox.hasPendingEntries())
    }

    @Test(
        .withMockedEnvironment(),
        .inTemporaryDirectory
    ) func drops_entries_older_than_the_servers_deduplication_window_unsent() async throws {
        try mockEnvironment()
        let outbox = try makeOutbox()
        let server = ScriptedServer([.status(502)])
        await #expect(throws: (any Error).self) {
            try await Client.$additionalMiddlewares.withValue([server]) { try await sendCommandEvent(outbox) }
        }

        clock.advance(by: 45 * 60 + 1)
        await Client.$additionalMiddlewares.withValue([server]) { await outbox.flush() }

        #expect(server.requests.count == 1)
        #expect(!outbox.hasPendingEntries())
    }

    @Test(
        .withMockedEnvironment(),
        .inTemporaryDirectory
    ) func replays_oldest_first_and_stops_at_the_first_transient_failure() async throws {
        try mockEnvironment()
        let outbox = try makeOutbox()
        let ids = ["0199f5a8-3c71-7a2b-9c1d-000000000001", "0199f5a8-3c71-7a2b-9c1d-000000000002"]
        let failing = ScriptedServer([.status(502), .status(502)])
        for id in ids {
            await #expect(throws: (any Error).self) {
                try await Client.$additionalMiddlewares.withValue([failing]) { try await sendCommandEvent(outbox, id: id) }
            }
            clock.advance(by: 1)
        }

        let down = ScriptedServer([.transport(.cannotConnectToHost)])
        await Client.$additionalMiddlewares.withValue([down]) { await outbox.flush() }
        #expect(down.requests.map(\.id) == [ids[0]])
        #expect(outbox.pendingFiles().count == 2)

        let up = ScriptedServer([.status(200), .status(200)])
        await Client.$additionalMiddlewares.withValue([up]) { await outbox.flush() }
        #expect(up.requests.map(\.id) == ids)
        #expect(!outbox.hasPendingEntries())
    }

    @Test(.withMockedEnvironment(), .inTemporaryDirectory) func removes_corrupt_entries() async throws {
        try mockEnvironment()
        let outbox = try makeOutbox()
        let directory = try outboxDirectory()
        let entry = ReportOutboxEntry(
            operation: .commandEvent, id: eventID, fullHandle: "acme/app", serverURL: serverURL, createdAt: clock.now
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not an entry".utf8).write(to: directory.appendingPathComponent(ReportOutbox.fileName(for: entry)))
        try Data("{}".utf8).write(to: directory.appendingPathComponent("unnamed.entry"))
        let undecodable = ReportOutboxEntry(
            operation: .testRun, id: eventID, fullHandle: "acme/app", serverURL: serverURL, createdAt: clock.now
        )
        try (JSONEncoder().encode(undecodable) + Data("\n{\"duration\":\"long\"}".utf8))
            .write(to: directory.appendingPathComponent(ReportOutbox.fileName(for: undecodable)))
        let server = ScriptedServer([])

        await Client.$additionalMiddlewares.withValue([server]) { await outbox.flush() }

        #expect(server.requests.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test(.withMockedEnvironment(), .inTemporaryDirectory) func bounds_the_number_of_entries() async throws {
        let outbox = try makeOutbox()
        var oldest: URL?
        for index in 0 ..< ReportOutbox.maximumEntryCount + 1 {
            let file = try writeEntry(createdAt: clock.now.addingTimeInterval(TimeInterval(index)), bodySize: 16)
            oldest = oldest ?? file
        }

        let files = outbox.pendingFiles()

        #expect(files.count == ReportOutbox.maximumEntryCount)
        #expect(try !files.contains(#require(oldest)))
    }

    @Test(.withMockedEnvironment(), .inTemporaryDirectory) func bounds_the_size_of_the_entries() async throws {
        let outbox = try makeOutbox()
        let size = 20 * 1024 * 1024
        let files = try (0 ..< 3)
            .map { try writeEntry(createdAt: clock.now.addingTimeInterval(TimeInterval($0)), bodySize: size) }

        #expect(outbox.pendingFiles() == Array(files.dropFirst()))
    }

    private func mockEnvironment() throws {
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_TOKEN"] = "project-token"
        environment.variables["TUIST_HTTP_MAXIMUM_RETRY_COUNT"] = "0"
    }

    private func outboxDirectory() throws -> URL {
        try #require(FileSystem.temporaryTestDirectory).appending(component: "report-outbox").url
    }

    private func makeOutbox() throws -> ReportOutbox {
        let clock = clock
        return try ReportOutbox(directory: outboxDirectory(), now: { clock.now })
    }

    private func writeEntry(createdAt: Date, bodySize: Int) throws -> URL {
        let directory = try outboxDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = ReportOutboxEntry(
            operation: .commandEvent, id: UUID().uuidString.lowercased(), fullHandle: "acme/app",
            serverURL: serverURL, createdAt: createdAt
        )
        let file = directory.appendingPathComponent(ReportOutbox.fileName(for: entry))
        try (JSONEncoder().encode(entry) + Data("\n".utf8) + Data(repeating: 0x20, count: bodySize)).write(to: file)
        return file
    }

    private func sendCommandEvent(_ outbox: ReportOutbox, id: String? = nil) async throws -> ServerCommandEvent {
        try await CreateCommandEventService(reportOutbox: outbox).createCommandEvent(
            commandEvent: .test(id: id ?? eventID),
            projectId: "acme/app",
            serverURL: serverURL
        )
    }

    #if canImport(TuistXCResultService)
        private func createTest(_ outbox: ReportOutbox, serverURL: URL? = nil) async throws -> Components.Schemas.RunsTest {
            try await CreateTestService(
                makeClient: { Client.reporting(serverURL: $0, networkTrusted: $1) },
                reportOutbox: outbox
            ).createTest(
                fullHandle: "acme/app", serverURL: serverURL ?? self.serverURL, id: eventID,
                testSummary: TestSummary(testPlanName: "App", status: .passed, duration: 1, testModules: []),
                buildRunId: nil, gitBranch: "main", gitCommitSHA: nil, gitRef: nil, gitRemoteURLOrigin: nil, isCI: true,
                modelIdentifier: nil, macOSVersion: "15", xcodeVersion: nil, ciRunId: nil, ciProjectHandle: nil,
                ciHost: nil, ciProvider: nil, shardPlanId: nil, shardIndex: nil, onlyTestIdentifiers: [],
                skipTestIdentifiers: []
            )
        }
    #endif

    private func withoutStoredCredentials(_ operation: () async -> Void) async {
        let credentials = MockServerCredentialsStoring()
        given(credentials).read(serverURL: .any).willReturn(nil)
        await CachedValueStore.$current.withValue(CachedValueStore(backend: .inSystemProcess)) {
            await ServerCredentialsStore.$current.withValue(credentials) {
                await operation()
            }
        }
    }
}

private final class TestClock: Sendable {
    private let date = Mutex(Date(timeIntervalSince1970: 1_761_130_000))

    var now: Date {
        date.withLock { $0 }
    }

    func advance(by interval: TimeInterval) {
        date.withLock { $0.addTimeInterval(interval) }
    }
}

extension ServerFailure {
    fileprivate var response: ScriptedServer.Response {
        switch self {
        case let .status(code): .status(code)
        case let .transport(code): .transport(code)
        }
    }
}

/// Answers each request with the next scripted response and records it.
private final class ScriptedServer: ClientMiddleware, Sendable {
    enum Response: Sendable {
        case status(Int)
        case transport(URLError.Code)
    }

    struct Request: Sendable {
        let operationID: String
        let id: String?
        let body: Data
        let authorized: Bool
    }

    private let responses: Mutex<[Response]>
    private let recorded = Mutex<[Request]>([])
    private let onRequest: @Sendable (Request) -> Void

    init(_ responses: [Response], onRequest: @escaping @Sendable (Request) -> Void = { _ in }) {
        self.responses = Mutex(responses)
        self.onRequest = onRequest
    }

    var requests: [Request] {
        recorded.withLock { $0 }
    }

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL _: URL,
        operationID: String,
        next _: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let data = try await Data(collecting: #require(body), upTo: .max)
        let id = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String
        let recordedRequest = Request(
            operationID: operationID,
            id: id,
            body: data,
            authorized: request.headerFields[.authorization] != nil
        )
        recorded.withLock { $0.append(recordedRequest) }
        onRequest(recordedRequest)
        let response = responses.withLock { $0.isEmpty ? Response.status(500) : $0.removeFirst() }
        switch response {
        case let .transport(code):
            throw URLError(code)
        case let .status(code) where (200 ..< 300).contains(code):
            var response = HTTPResponse(status: .init(code: code))
            response.headerFields[.contentType] = "application/json"
            let body = operationID == "createTest"
                ? #"{"type":"test","id":"\#(id ?? "")","duration":1,"project_id":1,"url":"https://tuist.dev/acme/app/tests/test-runs/1","test_case_runs":[]}"#
                : #"{"id":"\#(id ?? "")","project_id":1,"name":"generate","url":"https://tuist.dev/acme/app/runs/1"}"#
            return (response, HTTPBody(body))
        case let .status(code):
            var response = HTTPResponse(status: .init(code: code))
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(#"{"message":"rejected"}"#))
        }
    }
}
