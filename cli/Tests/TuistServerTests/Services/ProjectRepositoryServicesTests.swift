import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import TuistHTTP

@testable import TuistServer

struct ProjectRepositoryServicesTests {
    private let serverURL = URL(string: "https://tuist.example.com")!

    private func connectService(status: Int, json: String) -> ConnectProjectRepositoryService {
        ConnectProjectRepositoryService(makeClient: { url in
            Client(
                serverURL: url,
                transport: StubTransport(
                    status: status,
                    json: json,
                    method: .put,
                    operationID: "connectProjectRepository"
                )
            )
        })
    }

    private func disconnectService(status: Int, json: String) -> DisconnectProjectRepositoryService {
        DisconnectProjectRepositoryService(makeClient: { url in
            Client(
                serverURL: url,
                transport: StubTransport(
                    status: status,
                    json: json,
                    method: .delete,
                    operationID: "disconnectProjectRepository"
                )
            )
        })
    }

    @Test func connect_returns_the_canonical_repository_handle() async throws {
        let handle = try await connectService(
            status: 200,
            json: #"{"provider":"github","repository_full_handle":"Acme/App"}"#
        ).connectProjectRepository(fullHandle: "acme/ios", repositoryFullHandle: "acme/app", serverURL: serverURL)

        #expect(handle == "Acme/App")
    }

    @Test(arguments: [
        (400, ConnectProjectRepositoryServiceError.badRequest("message")),
        (403, .forbidden("message")),
        (404, .notFound("message")),
        (409, .conflict("message")),
        (422, .unprocessableContent("message")),
        (502, .badGateway("message")),
        (500, .unknownError(500)),
    ])
    func connect_maps_error_responses(status: Int, error: ConnectProjectRepositoryServiceError) async throws {
        await #expect(throws: error) {
            try await connectService(status: status, json: #"{"message":"message"}"#)
                .connectProjectRepository(fullHandle: "acme/ios", repositoryFullHandle: "acme/app", serverURL: serverURL)
        }
    }

    @Test func connect_preserves_retry_after_when_throttled() async throws {
        await #expect(throws: AuthorizationThrottledError(retryAfterSeconds: 7)) {
            try await connectService(status: 429, json: #"{"message":"slow down"}"#)
                .connectProjectRepository(fullHandle: "acme/ios", repositoryFullHandle: "acme/app", serverURL: serverURL)
        }
    }

    @Test func disconnect_succeeds_on_no_content() async throws {
        try await disconnectService(status: 204, json: "")
            .disconnectProjectRepository(fullHandle: "acme/ios", serverURL: serverURL)
    }

    @Test(arguments: [
        (403, DisconnectProjectRepositoryServiceError.forbidden("message")),
        (404, .notFound("message")),
        (500, .unknownError(500)),
    ])
    func disconnect_maps_error_responses(status: Int, error: DisconnectProjectRepositoryServiceError) async throws {
        await #expect(throws: error) {
            try await disconnectService(status: status, json: #"{"message":"message"}"#)
                .disconnectProjectRepository(fullHandle: "acme/ios", serverURL: serverURL)
        }
    }
}

private struct StubTransport: ClientTransport {
    let status: Int
    let json: String
    let method: HTTPRequest.Method
    let operationID: String

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        #expect(baseURL.absoluteString == "https://tuist.example.com")
        #expect(request.method == method)
        #expect(request.path == "/api/projects/acme/ios/vcs-connection")
        #expect(operationID == self.operationID)
        var response = HTTPResponse(status: .init(code: status))
        response.headerFields[.contentType] = "application/json"
        response.headerFields[.retryAfter] = "7"
        return (response, json.isEmpty ? nil : HTTPBody(json))
    }
}
