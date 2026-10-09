import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import TuistEnvironment

@testable import TuistServer

struct ServerClientActorHeadersMiddlewareTests {
    @Test func environment_resolution_and_override() {
        #expect(ServerClientActorHeadersMiddleware.actorID(variables: ["USER": "developer"]) == "developer")
        #expect(ServerClientActorHeadersMiddleware.actorID(variables: ["USERNAME": "windows-user"]) == "windows-user")
        #expect(ServerClientActorHeadersMiddleware
            .actorID(variables: ["TUIST_ACTOR_ID": "employee-123", "USER": "developer"]) == "employee-123")
        #expect(ServerClientActorHeadersMiddleware.actorID(variables: ["TUIST_ACTOR_ID": "", "USER": "developer"]) == nil)
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

    @Test(arguments: ["a\r\nb", "a b", "é", String(repeating: "a", count: 129)])
    func rejects_unsafe_identifiers(value: String) {
        #expect(ServerClientActorHeadersMiddleware.actorID(variables: ["TUIST_ACTOR_ID": value]) == nil)
    }

    @Test(arguments: [
        "createBuild",
        "createBuild (2)",
        "createTest",
        "createRun",
        "createCommandEvent",
        "createMixBuild",
        "createGradleBuild",
        "listBuilds",
        "getCacheEndpoints"
    ])
    func header_is_limited_to_report_creation(operation: String) async throws {
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
                        (ServerClientActorHeadersMiddleware.reportOperations.contains(operation) ? "employee-123" : nil))
                    return (HTTPResponse(status: .ok), nil)
                }
            }
        }
    }
}
