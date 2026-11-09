import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import TuistEnvironment
@testable import TuistServer

struct ServerClientRunnerHeadersMiddlewareTests {
    @Test func validates_grant_header() {
        for value in ["", "line\nbreak", "a b", String(repeating: "a", count: 8193)] {
            #expect(ServerClientRunnerHeadersMiddleware.grant(variables: ["TUIST_CACHE_SIGNING_GRANT": value]) == nil)
        }
        #expect(ServerClientRunnerHeadersMiddleware.grant(variables: ["TUIST_CACHE_SIGNING_GRANT": "a.b_c-d"]) == "a.b_c-d")
    }

    @Test(
        arguments: [
            "createShardPlan",
            "createBuild",
            "getShard",
            "startShardUpload",
            "generateShardUploadURL",
            "completeShardUpload"
        ],
        [true, false]
    )
    func forwards_only_for_linux_shard_operations(operation: String, isLinux: Bool) async throws {
        let environment = Environment(variables: ["TUIST_CACHE_SIGNING_GRANT": "signed.runner.grant"], arguments: [])
        try await Environment.$current.withValue(environment) {
            _ = try await ServerClientRunnerHeadersMiddleware(isLinux: isLinux).intercept(
                HTTPRequest(method: .post, scheme: "https", authority: "tuist.example", path: "/api"),
                body: nil,
                baseURL: try #require(URL(string: "https://tuist.example")),
                operationID: operation
            ) { request, _, _ in
                let header = try #require(HTTPField.Name("x-tuist-runner-grant"))
                #expect(request.headerFields[header] == (isLinux && operation != "createBuild" ? "signed.runner.grant" : nil))
                return (HTTPResponse(status: .ok), nil)
            }
        }
    }
}
