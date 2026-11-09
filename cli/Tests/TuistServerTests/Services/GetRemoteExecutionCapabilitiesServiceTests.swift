import Foundation
import Testing
import TuistEnvironment
import TuistTesting

@testable import TuistServer

struct GetRemoteExecutionCapabilitiesServiceTests {
    private let serverURL = URL(string: "https://tuist.dev")!

    @Test(.withMockedEnvironment())
    func reads_the_project_capabilities_with_the_cache_token() async throws {
        let requests = Requests()
        let subject = GetRemoteExecutionCapabilitiesService { request in
            requests.append(request)
            return Self.response(200, #"{"endpoint":"grpcs://execution.tuist.dev","image":"sha-0123456789ab","leases":true}"#)
        }

        let got = try await subject.getCapabilities(
            serverURL: serverURL, accountHandle: "tuist", projectHandle: "kura", token: "cache-token"
        )

        #expect(got == RemoteExecutionCapabilities(endpoint: "grpcs://execution.tuist.dev", image: "sha-0123456789ab"))
        let request = try #require(requests.all.first)
        #expect(request.url?.absoluteString == "https://tuist.dev/api/remote-execution/tuist/kura/capabilities")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer cache-token")
    }

    @Test(.withMockedEnvironment())
    func a_disabled_project_is_not_retried() async throws {
        let requests = Requests()
        let subject = GetRemoteExecutionCapabilitiesService { request in
            requests.append(request)
            return Self.response(403, #"{"message":"execution not authorized"}"#)
        }

        await #expect(throws: GetRemoteExecutionCapabilitiesServiceError.notEnabled) {
            try await subject.getCapabilities(
                serverURL: serverURL, accountHandle: "tuist", projectHandle: "kura", token: "cache-token"
            )
        }
        #expect(requests.all.count == 1)
    }

    private static func response(_ statusCode: Int, _ body: String) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: URL(string: "https://tuist.dev")!, statusCode: statusCode, httpVersion: nil, headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}

private final class Requests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    var all: [URLRequest] {
        lock.withLock { requests }
    }

    func append(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }
}
