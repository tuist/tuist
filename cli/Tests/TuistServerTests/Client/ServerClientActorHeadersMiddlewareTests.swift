import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import TuistEnvironment

@testable import TuistServer

struct ServerClientActorHeadersMiddlewareTests {
    @Test func environment_resolution_and_override() {
        #expect(ServerClientActorHeadersMiddleware.actorID(variables: ["USER": "developer"]) == nil)
        #expect(ServerClientActorHeadersMiddleware.actorID(variables: ["USERNAME": "windows-user"]) == nil)
        #expect(ServerClientActorHeadersMiddleware
            .actorID(variables: ["TUIST_ACTOR_ID": "employee-123", "USER": "developer"]) == "employee-123")
        #expect(ServerClientActorHeadersMiddleware.actorID(variables: ["TUIST_ACTOR_ID": "", "USER": "developer"]) == nil)
        #expect(ServerClientActorHeadersMiddleware.actorID(variables: ["USER": "", "LOGNAME": "fallback"]) == nil)
        let maximum = String(repeating: "~", count: 128)
        #expect(ServerClientActorHeadersMiddleware.actorID(variables: ["TUIST_ACTOR_ID": maximum]) == maximum)
    }

    @Test func omits_header_without_explicit_opt_in() async throws {
        let environment = Environment(
            variables: ["USER": "developer", "USERNAME": "windows-user", "LOGNAME": "legacy-user"],
            arguments: []
        )
        try await confirmation("Middleware forwards the request") { forwarded in
            try await Environment.$current.withValue(environment) {
                _ = try await ServerClientActorHeadersMiddleware().intercept(
                    HTTPRequest(method: .post, scheme: "https", authority: "tuist.example", path: "/api"),
                    body: nil,
                    baseURL: try #require(URL(string: "https://tuist.example")),
                    operationID: "createBuild"
                ) { request, _, _ in
                    forwarded()
                    let header = try #require(HTTPField.Name("x-tuist-actor-id"))
                    #expect(request.headerFields[header] == nil)
                    return (HTTPResponse(status: .ok), nil)
                }
            }
        }
    }

    @Test func preserves_explicit_request_override() async throws {
        let header = try #require(HTTPField.Name("x-tuist-actor-id"))
        var request = HTTPRequest(method: .post, scheme: "https", authority: "tuist.example", path: "/api")
        request.headerFields[header] = "explicit-actor"
        let preparedRequest = request
        let environment = Environment(variables: ["USER": "automatic-actor"], arguments: [])
        try await confirmation("Middleware forwards the request") { forwarded in
            try await Environment.$current.withValue(environment) {
                _ = try await ServerClientActorHeadersMiddleware().intercept(
                    preparedRequest,
                    body: nil,
                    baseURL: try #require(URL(string: "https://tuist.example")),
                    operationID: "createBuild"
                ) { request, _, _ in
                    forwarded()
                    #expect(request.headerFields[header] == "explicit-actor")
                    return (HTTPResponse(status: .ok), nil)
                }
            }
        }
    }

    @Test func legacy_authenticated_request_and_response_are_unchanged() async throws {
        let authorization = try #require(HTTPField.Name("authorization"))
        var request = HTTPRequest(
            method: .post,
            scheme: "https",
            authority: "tuist.example",
            path: "/api/projects/acme/app/builds"
        )
        request.headerFields[authorization] = "Bearer existing-token"
        let preparedRequest = request
        let payload = "{\"id\":\"build-id\",\"duration\":42}"
        let legacyResponse = "{\"id\":\"build-id\"}"
        let environment = Environment(variables: ["TUIST_ACTOR_ID": "employee-123"], arguments: [])
        try await Environment.$current.withValue(environment) {
            let (response, responseBody) = try await ServerClientActorHeadersMiddleware().intercept(
                preparedRequest,
                body: HTTPBody(payload),
                baseURL: try #require(URL(string: "https://tuist.example")),
                operationID: "createBuild"
            ) { request, body, url in
                #expect(request.headerFields[authorization] == "Bearer existing-token")
                #expect(request.path == preparedRequest.path)
                #expect(url.absoluteString == "https://tuist.example")
                let requestBody = try #require(body)
                #expect(try await String(collecting: requestBody, upTo: 1024) == payload)
                return (HTTPResponse(status: .created), HTTPBody(legacyResponse))
            }
            #expect(response.status == .created)
            let body = try #require(responseBody)
            #expect(try await String(collecting: body, upTo: 1024) == legacyResponse)
        }
    }

    @Test(arguments: ["a\r\nb", "a b", "é", String(repeating: "a", count: 129)])
    func rejects_unsafe_identifiers(value: String) {
        #expect(ServerClientActorHeadersMiddleware.actorID(variables: ["TUIST_ACTOR_ID": value, "USER": "fallback"]) == nil)
    }

    @Test(arguments: [
        ("createBuild", true),
        ("createBuild (2)", true),
        ("createTest", true),
        ("createRun", true),
        ("createCommandEvent", true),
        ("createMixBuild", true),
        ("createGradleBuild", true),
        ("listBuilds", false),
        ("getCacheEndpoints", false),
        ("getTest", false),
        ("createTestShardPlan", false),
        ("createTestCaseRunAttachment", false),
        ("createAccountToken", false)
    ])
    func header_is_limited_to_report_creation(operation: String, shouldAttach: Bool) async throws {
        let environment = Environment(variables: ["TUIST_ACTOR_ID": "employee-123"], arguments: [])
        try await confirmation("Middleware forwards the request") { forwarded in
            try await Environment.$current.withValue(environment) {
                _ = try await ServerClientActorHeadersMiddleware().intercept(
                    HTTPRequest(method: .post, scheme: "https", authority: "tuist.example", path: "/api"),
                    body: nil,
                    baseURL: try #require(URL(string: "https://tuist.example")),
                    operationID: operation
                ) { request, _, _ in
                    forwarded()
                    let name = try #require(HTTPField.Name("x-tuist-actor-id"))
                    let header = request.headerFields[name]
                    #expect(header ==
                        (shouldAttach ? "employee-123" : nil))
                    return (HTTPResponse(status: .ok), nil)
                }
            }
        }
    }
}
