import Foundation
import Synchronization
import Testing

@testable import TuistAuthentication

struct AppServerInfoServiceTests {
    private static let server = URL(string: "https://server.example.com:8443/tuist")!

    @Test(arguments: ["1.37.0", "2026.10.16-canary.4", "git-abcdef", "next-release"])
    func versions_are_informational_not_restricted_to_semver(version: String) async {
        let subject = AppServerInfoService(perform: { request in
            #expect(request.url?.absoluteString == "https://server.example.com:8443/tuist/.well-known/tuist")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.timeoutInterval == 10)
            return Self.response(request, json: #"{"version":"\#(version)"}"#)
        })

        #expect(await subject.version(for: Self.server) == version)
    }

    @Test func future_fields_are_ignored() async {
        let subject = AppServerInfoService(perform: {
            Self.response($0, json: #"{"version":" 1.37.0 ","capabilities":{"future":true},"schema_version":2}"#)
        })
        #expect(await subject.version(for: Self.server) == "1.37.0")
    }

    @Test(arguments: [
        "{}", #"{"version":null}"#, #"{"version":""}"#, #"{"version":"  "}"#,
        #"{"version":42}"#, #"{"version":{"major":1}}"#, "[]", "not json",
        #"{"version":"one\ntwo"}"#, "{\"version\":\"\(String(repeating: "a", count: 129))\"}",
    ])
    func absent_or_unusable_metadata_is_optional(json: String) async {
        let subject = AppServerInfoService(perform: { Self.response($0, json: json) })
        #expect(await subject.version(for: Self.server) == nil)
    }

    @Test(arguments: [301, 302, 401, 403, 404, 405, 429, 500, 503])
    func old_servers_and_failed_responses_do_not_break_the_client(status: Int) async {
        let subject = AppServerInfoService(perform: { Self.response($0, status: status, json: #"{"version":"1.0"}"#) })
        #expect(await subject.version(for: Self.server) == nil)
    }

    @Test func network_failures_are_nonfatal() async {
        let subject = AppServerInfoService(perform: { _ in throw URLError(.notConnectedToInternet) })
        #expect(await subject.version(for: Self.server) == nil)
    }

    @Test func redirected_metadata_is_not_attributed_to_the_selected_server() async {
        let subject = AppServerInfoService(perform: { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://other.example.com/.well-known/tuist")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (Data(#"{"version":"other-server"}"#.utf8), response)
        })
        #expect(await subject.version(for: Self.server) == nil)
    }

    @Test func oversized_metadata_is_ignored() async {
        let subject = AppServerInfoService(perform: {
            Self.response($0, json: "{\"version\":\"1\",\"future\":\"\(String(repeating: "a", count: 65536))\"}")
        })
        #expect(await subject.version(for: Self.server) == nil)
    }

    @Test func each_lookup_uses_its_own_scheme_host_port_and_base_path() async {
        let requests = Mutex<[URL]>([])
        let subject = AppServerInfoService(perform: { request in
            requests.withLock { $0.append(request.url!) }
            return Self.response(request, json: #"{"version":"\#(request.url!.absoluteString)"}"#)
        })
        let urls = [
            "https://server.example.com", "https://other.example.com", "http://server.example.com",
            "https://server.example.com:8443", "https://server.example.com/tuist",
        ].map { URL(string: $0)! }
        for url in urls {
            let first = await subject.version(for: url)
            #expect(first == url.appending(path: ".well-known/tuist").absoluteString)
            #expect(await subject.version(for: url) == first)
        }
        #expect(requests.withLock { $0.count } == urls.count * 2)
    }

    @Test func an_old_server_can_be_upgraded_between_lookups() async {
        let requests = Mutex(0)
        let subject = AppServerInfoService(perform: { request in
            let count = requests.withLock { $0 += 1; return $0 }
            return Self.response(request, status: count == 1 ? 404 : 200, json: #"{"version":"upgraded"}"#)
        })
        #expect(await subject.version(for: Self.server) == nil)
        #expect(await subject.version(for: Self.server) == "upgraded")
    }

    @Test func cancellation_does_not_prevent_retrying() async {
        let requests = Mutex(0)
        let subject = AppServerInfoService(perform: { request in
            let count = requests.withLock { $0 += 1; return $0 }
            if count == 1 { throw CancellationError() }
            return Self.response(request, json: #"{"version":"retry"}"#)
        })
        #expect(await subject.version(for: Self.server) == nil)
        #expect(await subject.version(for: Self.server) == "retry")
    }

    @Test func cancelled_late_responses_are_discarded() async {
        let pending = PendingServerInfoResponse()
        let requests = Mutex(0)
        let subject = AppServerInfoService(perform: { request in
            let count = requests.withLock { $0 += 1; return $0 }
            if count == 1 { return await pending.response(for: request) }
            return Self.response(request, json: #"{"version":"fresh"}"#)
        })
        let task = Task { await subject.version(for: Self.server) }
        await pending.waitUntilRequested()
        task.cancel()
        await pending.resume(version: "cancelled")

        #expect(await task.value == nil)
        #expect(await subject.version(for: Self.server) == "fresh")
    }

    @Test func late_metadata_is_never_reused_for_another_server() async {
        let pending = PendingServerInfoResponse()
        let other = URL(string: "https://other.example.com")!
        let requests = Mutex(0)
        let subject = AppServerInfoService(perform: { request in
            let count = requests.withLock { $0 += 1; return $0 }
            if count == 1 { return await pending.response(for: request) }
            return Self.response(request, json: #"{"version":"other"}"#)
        })
        let task = Task { await subject.version(for: Self.server) }
        await pending.waitUntilRequested()
        #expect(await subject.version(for: other) == "other")
        await pending.resume(version: "original")
        #expect(await task.value == "original")
        #expect(await subject.version(for: other) == "other")
    }

    @Test func transport_uses_no_cookies_credentials_or_cache_and_refuses_redirects() async throws {
        let session = AppServerInfoService.makeSession()
        defer { session.invalidateAndCancel() }
        #expect(session.configuration.httpCookieStorage == nil)
        #expect(!session.configuration.httpShouldSetCookies)
        #expect(session.configuration.urlCredentialStorage == nil)
        #expect(session.configuration.urlCache == nil)
        let delegate = try #require(session.delegate as? URLSessionTaskDelegate)
        let request = URLRequest(url: Self.server)
        let response = HTTPURLResponse(url: Self.server, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let refused = Mutex(false)
        delegate.urlSession?(
            session, task: session.dataTask(with: request),
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: "https://other.example.com")!)
        ) { redirect in
            #expect(redirect == nil)
            refused.withLock { $0 = true }
        }
        #expect(refused.withLock { $0 })
    }

    @Test(arguments: ["declared-oversize", "streamed-oversize"])
    func transport_bounds_the_response_before_decoding(fixture: String) async {
        let session = Self.fixtureSession()
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://server-info.test/\(fixture)")!)
        await #expect(throws: URLError(.dataLengthExceedsMaximum)) {
            _ = try await AppServerInfoService.load(request, session: session)
        }
    }

    @Test func transport_accepts_a_response_at_the_size_limit() async throws {
        let session = Self.fixtureSession()
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://server-info.test/limit")!)
        let (data, _) = try await AppServerInfoService.load(request, session: session)
        #expect(data.count == AppServerInfoService.maximumResponseSize)
    }

    private static func fixtureSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServerInfoURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(_ request: URLRequest, status: Int = 200, json: String) -> (Data, URLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private final class ServerInfoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "server-info.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let limit = AppServerInfoService.maximumResponseSize
        let declared = request.url?.lastPathComponent == "declared-oversize"
        let count = request.url?.lastPathComponent == "limit" ? limit : limit + 1
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: declared ? ["Content-Length": "\(count)"] : [:]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 32, count: count))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor PendingServerInfoResponse {
    private var request: URLRequest?
    private var continuation: CheckedContinuation<(Data, URLResponse), Never>?

    func response(for request: URLRequest) async -> (Data, URLResponse) {
        self.request = request
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilRequested() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func resume(version: String) {
        let response = HTTPURLResponse(url: request!.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        continuation?.resume(returning: (Data(#"{"version":"\#(version)"}"#.utf8), response))
        continuation = nil
    }
}
