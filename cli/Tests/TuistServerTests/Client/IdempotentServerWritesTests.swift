import Foundation
import HTTPTypes
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

struct IdempotentServerWritesTests {
    private let serverURL = URL(string: "https://test.tuist.dev")!

    @Test(.withMockedEnvironment(), arguments: [ServerFailure.status(502), .transport(.networkConnectionLost)])
    func replays_a_command_event_with_the_id_it_generated(failure: ServerFailure) async throws {
        try mockEnvironment()
        let server = ReplayingServer(operationID: "createCommandEvent", failure: failure) { id in
            #"{"id":"\#(id)","project_id":1,"name":"test","url":"https://tuist.dev/acme/app/runs/\#(id)"}"#
        }

        let event = try await Client.$additionalMiddlewares.withValue([server]) {
            try await CreateCommandEventService().createCommandEvent(
                commandEvent: .test(),
                projectId: "acme/app",
                serverURL: serverURL
            )
        }

        let ids = server.ids
        let id = try #require(ids.first ?? nil)
        #expect(ids == [id, id])
        #expect(Self.isUUIDv7(id))
        #expect(event.id == id)
    }

    @Test(.withMockedEnvironment())
    func replays_a_command_event_with_the_generation_id() async throws {
        try mockEnvironment()
        let server = ReplayingServer(operationID: "createCommandEvent", failure: .status(502)) { id in
            #"{"id":"\#(id)","project_id":1,"name":"generate","url":"https://tuist.dev/acme/app/runs/\#(id)"}"#
        }

        _ = try await Client.$additionalMiddlewares.withValue([server]) {
            try await CreateCommandEventService().createCommandEvent(
                commandEvent: .test(generationId: "generation-id"),
                projectId: "acme/app",
                serverURL: serverURL
            )
        }

        #expect(server.ids == ["generation-id", "generation-id"])
    }

    @Test(.withMockedEnvironment(), arguments: [ServerFailure.status(502), .status(503), .transport(.networkConnectionLost)])
    func replays_a_cargo_test_report_with_the_id_it_generated(failure: ServerFailure) async throws {
        try mockEnvironment()
        let server = ReplayingServer(operationID: "createTest", failure: failure, respond: Self.testRun)

        try await Client.$additionalMiddlewares.withValue([server]) {
            try await CargoReportService().submit(
                Data(#"{"duration":1,"is_ci":false,"test_modules":[]}"#.utf8),
                fullHandle: "acme/app",
                serverURL: serverURL,
                kind: "tests"
            )
        }

        let ids = server.ids
        let id = try #require(ids.first ?? nil)
        #expect(ids == [id, id])
        #expect(Self.isUUIDv7(id))
    }

    @Test(.withMockedEnvironment(), arguments: [ServerFailure.status(502), .transport(.networkConnectionLost)])
    func replays_a_token_refresh_after_an_ambiguous_failure(failure: ServerFailure) async throws {
        try mockEnvironment()
        let server = ReplayingServer(operationID: "refreshToken", failure: failure) { _ in
            #"{"access_token":"access","refresh_token":"rotated"}"#
        }

        let tokens = try await Client.$additionalMiddlewares.withValue([server]) {
            try await RefreshAuthTokenService().refreshTokens(serverURL: serverURL, refreshToken: "refresh")
        }

        #expect(server.attempts == 2)
        #expect(tokens.refreshToken == "rotated")
    }

    #if canImport(TuistXCResultService)
        @Test(.withMockedEnvironment(), arguments: [ServerFailure.status(502), .status(503), .transport(.networkConnectionLost)])
        func replays_a_test_run_with_the_id_it_generated(failure: ServerFailure) async throws {
            try mockEnvironment()
            let server = ReplayingServer(operationID: "createTest", failure: failure, respond: Self.testRun)

            let test = try await Client.$additionalMiddlewares.withValue([server]) {
                try await createTest(id: nil)
            }

            let ids = server.ids
            let id = try #require(ids.first ?? nil)
            #expect(ids == [id, id])
            #expect(Self.isUUIDv7(id))
            #expect(test.id == id)
        }

        @Test(.withMockedEnvironment())
        func replays_a_test_run_with_the_id_the_caller_prepared() async throws {
            try mockEnvironment()
            let server = ReplayingServer(operationID: "createTest", failure: .status(502), respond: Self.testRun)

            _ = try await Client.$additionalMiddlewares.withValue([server]) {
                try await createTest(id: "prepared-id")
            }

            #expect(server.ids == ["prepared-id", "prepared-id"])
        }

        private func createTest(id: String?) async throws -> Components.Schemas.RunsTest {
            try await CreateTestService().createTest(
                fullHandle: "acme/app", serverURL: serverURL, id: id,
                testSummary: TestSummary(testPlanName: nil, status: .passed, duration: 1, testModules: []),
                buildRunId: nil, gitBranch: nil, gitCommitSHA: nil, gitRef: nil, gitRemoteURLOrigin: nil, isCI: false,
                modelIdentifier: nil, macOSVersion: "15", xcodeVersion: nil, ciRunId: nil, ciProjectHandle: nil,
                ciHost: nil, ciProvider: nil, shardPlanId: nil, shardIndex: nil, onlyTestIdentifiers: [],
                skipTestIdentifiers: []
            )
        }
    #endif

    private func mockEnvironment() throws {
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_TOKEN"] = "project-token"
        environment.variables["TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS"] = "0"
    }

    private static func testRun(id: String) -> String {
        #"{"type":"test","id":"\#(id)","duration":1,"project_id":1,"url":"https://tuist.dev/acme/app/tests/test-runs/\#(id)","test_case_runs":[]}"#
    }

    private static func isUUIDv7(_ id: String) -> Bool {
        UUID(uuidString: id) != nil && id == id.lowercased() && Array(id)[14] == "7"
    }
}

enum ServerFailure: Sendable, CustomTestStringConvertible {
    case status(Int)
    case transport(URLError.Code)

    var testDescription: String {
        switch self {
        case let .status(code): "HTTP \(code)"
        case let .transport(code): "URLError \(code.rawValue)"
        }
    }
}

/// Answers the first request with `failure` and every later one with `respond`'s body, recording each request's `id`.
private final class ReplayingServer: ClientMiddleware, Sendable {
    private let operationID: String
    private let failure: ServerFailure
    private let respond: @Sendable (String) -> String
    private let requestIDs = Mutex<[String?]>([])

    init(operationID: String, failure: ServerFailure, respond: @escaping @Sendable (String) -> String) {
        self.operationID = operationID
        self.failure = failure
        self.respond = respond
    }

    var ids: [String?] {
        requestIDs.withLock { $0 }
    }

    var attempts: Int {
        ids.count
    }

    func intercept(
        _: HTTPRequest,
        body: HTTPBody?,
        baseURL _: URL,
        operationID: String,
        next _: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        #expect(operationID == self.operationID)
        let data = try await Data(collecting: #require(body), upTo: .max)
        let id = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String
        let attempt = requestIDs.withLock { ids in
            ids.append(id)
            return ids.count
        }
        if attempt == 1 {
            switch failure {
            case let .status(code):
                return (HTTPResponse(status: .init(code: code)), nil)
            case let .transport(code):
                throw URLError(code)
            }
        }
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(respond(id ?? "")))
    }
}
