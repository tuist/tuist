import Foundation
import Testing
@testable import SwifterPMCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct HTTPClientTests {
    @Test
    func retriesRequestTimeoutUntilItSucceeds() async throws {
        try await withLocalHTTPServer { server in
            server.respond(
                to: "/archive.zip",
                with: [.status(408), .status(408), .ok("payload")]
            )

            let data = try await HTTPClient.data(url: server.url(path: "/archive.zip"))

            #expect(String(data: data, encoding: .utf8) == "payload")
            #expect(server.requestedPaths == ["/archive.zip", "/archive.zip", "/archive.zip"])
        }
    }

    @Test
    func retriesServiceUnavailableAndTooManyRequests() async throws {
        for status in [429, 503] {
            try await withLocalHTTPServer { server in
                server.respond(to: "/archive.zip", with: [.status(status), .ok("payload")])

                let data = try await HTTPClient.data(url: server.url(path: "/archive.zip"))

                #expect(String(data: data, encoding: .utf8) == "payload")
                #expect(server.requestedPaths.count == 2)
            }
        }
    }

    @Test
    func doesNotRetryClientErrors() async throws {
        try await withLocalHTTPServer { server in
            server.respond(to: "/archive.zip", with: [.status(404)])

            await #expect(throws: (any Error).self) {
                try await HTTPClient.data(url: server.url(path: "/archive.zip"))
            }
            #expect(server.requestedPaths == ["/archive.zip"])
        }
    }

    @Test
    func reportsTheURLThatActuallyFailedAfterARedirect() async throws {
        try await withLocalHTTPServer { server in
            server.respond(to: "/registry.zip", with: [.redirect(to: "/storage.zip")])
            server.respond(to: "/storage.zip", with: [.status(408)])

            let error = await #expect(throws: (any Error).self) {
                try await HTTPClient.data(url: server.url(path: "/registry.zip"))
            }

            let message = String(describing: try #require(error))
            #expect(message.contains("/storage.zip"))
            #expect(!message.contains("/registry.zip"))
        }
    }

    @Test
    func surfacesTheStatusCodeInTheMessage() async throws {
        try await withLocalHTTPServer { server in
            server.respond(to: "/archive.zip", with: [.status(404)])

            let error = await #expect(throws: (any Error).self) {
                try await HTTPClient.data(url: server.url(path: "/archive.zip"))
            }

            let message = String(describing: try #require(error))
            #expect(message.contains("HTTP 404"))
        }
    }

    @Test
    func doesNotLeakRedirectCredentialsIntoTheMessage() async throws {
        try await withLocalHTTPServer { server in
            let signed = "/storage.zip?X-Amz-Credential=AKIAEXAMPLE&X-Amz-Signature=deadbeefsecret"
            server.respond(to: "/registry.zip", with: [.redirect(to: signed)])
            server.respond(to: "/storage.zip", with: [.status(408)])

            let error = await #expect(throws: (any Error).self) {
                try await HTTPClient.data(url: server.url(path: "/registry.zip"))
            }

            let message = String(describing: try #require(error))
            #expect(message.contains("HTTP 408"))
            #expect(message.contains("/storage.zip"))
            #expect(!message.contains("deadbeefsecret"))
            #expect(!message.contains("X-Amz-Signature"))
            #expect(!message.contains("AKIAEXAMPLE"))
        }
    }

    @Test
    func redactsUserInfoQueryAndFragment() throws {
        let url = try #require(
            URL(string: "https://user:pass@storage.example/a/b.zip?token=secret#frag"))

        let redacted = HTTPClient.StatusError.redactingCredentials(url)

        #expect(redacted == "https://storage.example/a/b.zip")
    }

    @Test
    func successfulResponsesProduceNoError() throws {
        #expect(makeStatusError(statusCode: 200) == nil)
        #expect(makeStatusError(statusCode: 204) == nil)
    }

    @Test
    func classifiesTransientStatusesAsRetryable() throws {
        for statusCode in [408, 429, 500, 502, 503, 504] {
            let error = try #require(makeStatusError(statusCode: statusCode))
            #expect(error.isRetryable, "expected \(statusCode) to be retryable")
        }

        for statusCode in [400, 401, 403, 404, 410, 422] {
            let error = try #require(makeStatusError(statusCode: statusCode))
            #expect(!error.isRetryable, "expected \(statusCode) not to be retryable")
        }
    }

    @Test
    func readsRetryAfterAndBoundsIt() throws {
        let honoured = try #require(
            makeStatusError(statusCode: 429, headers: ["Retry-After": " 5 "]))
        #expect(honoured.retryAfter == 5)

        let bounded = try #require(
            makeStatusError(statusCode: 429, headers: ["Retry-After": "86400"]))
        #expect(bounded.retryAfter == HTTPClient.StatusError.maximumRetryAfter)

        let absent = try #require(makeStatusError(statusCode: 429))
        #expect(absent.retryAfter == nil)

        let unparsable = try #require(
            makeStatusError(statusCode: 429, headers: ["Retry-After": "not-a-delay"]))
        #expect(unparsable.retryAfter == nil)
    }

    @Test
    func readsRetryAfterExpressedAsAnHTTPDate() throws {
        let now = Date(timeIntervalSince1970: 1_787_707_171)

        let imfFixdate = try #require(
            makeStatusError(
                statusCode: 503,
                headers: ["Retry-After": "Wed, 26 Aug 2026 01:19:41 GMT"],
                now: now
            ))
        #expect(imfFixdate.retryAfter == 10)

        let bounded = try #require(
            makeStatusError(
                statusCode: 503,
                headers: ["Retry-After": "Thu, 27 Aug 2026 01:19:31 GMT"],
                now: now
            ))
        #expect(bounded.retryAfter == HTTPClient.StatusError.maximumRetryAfter)

        let past = try #require(
            makeStatusError(
                statusCode: 503,
                headers: ["Retry-After": "Tue, 25 Aug 2026 01:19:31 GMT"],
                now: now
            ))
        #expect(past.retryAfter == nil)

        let asctime = try #require(
            makeStatusError(
                statusCode: 503,
                headers: ["Retry-After": "Wed Aug 26 01:19:41 2026"],
                now: now
            ))
        #expect(asctime.retryAfter == 10)
    }

    private func makeStatusError(
        statusCode: Int,
        headers: [String: String] = [:],
        respondingURL: URL? = nil,
        requestedURL: URL = URL(string: "https://tuist.dev/registry.zip")!,
        now: Date = Date()
    ) -> HTTPClient.StatusError? {
        let response = HTTPURLResponse(
            url: respondingURL ?? requestedURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return HTTPClient.StatusError(response: response, requestedURL: requestedURL, now: now)
    }
}
