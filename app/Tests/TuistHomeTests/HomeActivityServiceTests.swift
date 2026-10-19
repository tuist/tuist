import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import TuistServer

@testable import TuistHome

struct HomeActivityServiceTests {
    @Test(arguments: HomeActivityKind.allCases)
    func requests_the_selected_project_and_maps_browser_links(kind: HomeActivityKind) async throws {
        let service = subject(kind, status: 200, json: """
        {"items":[{"id":"run-id","title":"AppTests","subtitle":"main","occurred_at":1700000000,
        "url":"/sample/one/tests/test-runs/run-id","future_field":true}],"future_field":true}
        """)

        let items = try await service.fetch(kind, fullHandle: "sample/one", serverURL: serverURL)

        #expect(items.map(\.id) == ["run-id"])
        #expect(items.first?.url.absoluteString == "https://example.invalid/deployment/sample/one/tests/test-runs/run-id")
        #expect(items.first?.occurredAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test(arguments: [404, 401, 429, 500, 503])
    func old_servers_and_failures_are_not_reported_as_no_failures(status: Int) async {
        await #expect(throws: HomeActivityError.unavailable) {
            try await subject(.buildFailures, status: status, json: "{\"message\":\"Unavailable\"}")
                .fetch(.buildFailures, fullHandle: "sample/one", serverURL: serverURL)
        }
    }

    @Test(arguments: [403, 422])
    func reports_permission_and_unsupported_sections(status: Int) async {
        await #expect(throws: status == 403 ? HomeActivityError.forbidden : .unsupported) {
            try await subject(.testFailures, status: status, json: "{\"message\":\"Unavailable\"}")
                .fetch(.testFailures, fullHandle: "sample/one", serverURL: serverURL)
        }
    }

    @Test func an_empty_success_is_a_genuine_empty_list() async throws {
        let items = try await subject(.flakyTests, status: 200, json: "{\"items\":[]}")
            .fetch(.flakyTests, fullHandle: "sample/one", serverURL: serverURL)
        #expect(items.isEmpty)
    }

    @Test(arguments: [
        "https://evil.invalid/sample/one/tests/test-runs/id", "//evil.invalid/sample/one/tests/test-runs/id",
        "/someone/else/tests/test-runs/id", "/sample/one/../../id", "/sample/one/%2e%2e/id",
        "/sample/one/tests/test-runs/id?token=unexpected", "/sample/one/tests/test-runs/id#fragment",
    ])
    func rejects_foreign_or_escaping_dashboard_paths(path: String) {
        #expect(throws: HomeActivityError.invalidResponse) {
            try HomeActivityService.dashboardURL(path, fullHandle: "sample/one", serverURL: serverURL)
        }
    }

    @Test(arguments: [
        "https://example.invalid:8443/base",
        "https://example.invalid:8443/base/",
        "https://example.invalid:8443/sample"
    ])
    func retains_ports_and_the_complete_deployment_base_path(base: String) throws {
        let url = try HomeActivityService.dashboardURL(
            "/sample/one/tests/test-cases/id", fullHandle: "sample/one", serverURL: URL(string: base)!
        )
        #expect(url.absoluteString == base
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/sample/one/tests/test-cases/id")
    }

    private var serverURL: URL { URL(string: "https://example.invalid/deployment")! }

    private func subject(_ kind: HomeActivityKind, status: Int, json: String) -> HomeActivityService {
        HomeActivityService(makeClient: { url in
            Client(serverURL: url, transport: ActivityTransport(kind: kind, status: status, json: json))
        })
    }
}

private struct ActivityTransport: ClientTransport {
    let kind: HomeActivityKind
    let status: Int
    let json: String

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let suffix = switch kind {
        case .buildFailures: "build-failures"
        case .testFailures: "test-failures"
        case .flakyTests: "flaky-tests"
        }
        let operation = switch kind {
        case .buildFailures: "getHomeBuildFailures"
        case .testFailures: "getHomeTestFailures"
        case .flakyTests: "getHomeFlakyTests"
        }
        #expect(baseURL.absoluteString == "https://example.invalid/deployment")
        #expect(request.method == .get)
        #expect(request.path == "/api/projects/sample/one/home/\(suffix)")
        #expect(operationID == operation)
        var response = HTTPResponse(status: .init(code: status))
        response.headerFields[.contentType] = "application/json"
        response.headerFields[.retryAfter] = "7"
        response.headerFields[HTTPField.Name("x-tuist-throttle-reason")!] = "authorization"
        return (response, HTTPBody(json))
    }
}
