import Foundation
import Testing

@testable import TuistHTTP
@testable import TuistSupport

struct HAREntryBuilderTests {
    private let subject = HAREntryBuilder()

    @Test
    func buildEntry_createsCorrectEntry() {
        // Given
        let url = URL(string: "https://api.example.com/v1/test?key=value")!
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(0.5)
        let requestHeaders = [HAR.Header(name: "Content-Type", value: "application/json")]
        let responseHeaders = [HAR.Header(name: "Content-Type", value: "application/json")]
        let requestBody = "request body".data(using: .utf8)
        let responseBody = "response body".data(using: .utf8)

        // When
        let entry = subject.buildEntry(
            url: url,
            method: "POST",
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseStatusCode: 200,
            responseStatusText: "OK",
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            startTime: startTime,
            endTime: endTime
        )

        // Then
        #expect(entry.request.method == "POST")
        #expect(entry.request.url == "https://api.example.com/v1/test?key=value")
        #expect(entry.request.httpVersion == "HTTP/1.1")
        #expect(entry.response.status == 200)
        #expect(entry.response.statusText == "OK")
        #expect(entry.time == 500)
    }

    @Test
    func buildEntry_filtersSensitiveHeaders() {
        // Given
        let url = URL(string: "https://api.example.com/test")!
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(0.1)
        let requestHeaders = [
            HAR.Header(name: "Authorization", value: "Bearer secret-token"),
            HAR.Header(name: "Content-Type", value: "application/json"),
        ]
        let responseHeaders = [
            HAR.Header(name: "Set-Cookie", value: "session=abc123"),
            HAR.Header(name: "Content-Type", value: "application/json"),
        ]

        // When
        let entry = subject.buildEntry(
            url: url,
            method: "GET",
            requestHeaders: requestHeaders,
            requestBody: nil,
            responseStatusCode: 200,
            responseStatusText: "OK",
            responseHeaders: responseHeaders,
            responseBody: nil,
            startTime: startTime,
            endTime: endTime
        )

        // Then
        let authHeader = entry.request.headers.first { $0.name == "Authorization" }
        #expect(authHeader?.value == "[REDACTED]")

        let cookieHeader = entry.response.headers.first { $0.name == "Set-Cookie" }
        #expect(cookieHeader?.value == "[REDACTED]")

        let contentTypeHeader = entry.request.headers.first { $0.name == "Content-Type" }
        #expect(contentTypeHeader?.value == "application/json")
    }

    @Test
    func buildEntry_extractsQueryParameters() {
        // Given
        let url = URL(string: "https://api.example.com/test?foo=bar&baz=qux")!
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(0.1)

        // When
        let entry = subject.buildEntry(
            url: url,
            method: "GET",
            requestHeaders: [],
            requestBody: nil,
            responseStatusCode: 200,
            responseStatusText: "OK",
            responseHeaders: [],
            responseBody: nil,
            startTime: startTime,
            endTime: endTime
        )

        // Then
        #expect(entry.request.queryString.count == 2)
        #expect(entry.request.queryString.contains { $0.name == "foo" && $0.value == "bar" })
        #expect(entry.request.queryString.contains { $0.name == "baz" && $0.value == "qux" })
    }

    @Test
    func buildErrorEntry_createsCorrectEntry() {
        // Given
        let url = URL(string: "https://api.example.com/test")!
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(1.0)
        let error = NSError(domain: "TestError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Test error"])

        // When
        let entry = subject.buildErrorEntry(
            url: url,
            method: "POST",
            requestHeaders: [],
            requestBody: nil,
            error: error,
            startTime: startTime,
            endTime: endTime
        )

        // Then
        #expect(entry.request.method == "POST")
        #expect(entry.response.status == 0)
        #expect(entry.response.statusText == "Error")
        #expect(entry.response.content.mimeType == "text/plain")
        #expect(entry.response.content.text?.contains("TestError") == true)
        #expect(entry.time == 1000)
    }

    @Test
    func extractQueryParameters_returnsEmptyForNoQuery() {
        // Given
        let url = URL(string: "https://api.example.com/test")!

        // When
        let params = subject.extractQueryParameters(from: url)

        // Then
        #expect(params.isEmpty)
    }

    @Test
    func buildURL_appendsPathToBase() {
        // Given
        let baseURL = URL(string: "https://api.example.com")!

        // When
        let result = subject.buildURL(baseURL: baseURL, path: "/v1/test")

        // Then
        #expect(result.absoluteString == "https://api.example.com/v1/test")
    }

    @Test
    func buildURL_handlesNilPath() {
        // Given
        let baseURL = URL(string: "https://api.example.com")!

        // When
        let result = subject.buildURL(baseURL: baseURL, path: nil)

        // Then
        #expect(result.absoluteString == "https://api.example.com")
    }

    @Test
    func buildURL_handlesPathWithQueryParameters() {
        // Given
        let baseURL = URL(string: "https://api.example.com")!

        // When
        let result = subject.buildURL(baseURL: baseURL, path: "/v1/test?foo=bar&baz=qux")

        // Then
        #expect(result.absoluteString == "https://api.example.com/v1/test?foo=bar&baz=qux")
    }

    @Test
    func buildURL_handlesPathWithoutLeadingSlash() {
        // Given
        let baseURL = URL(string: "https://api.example.com")!

        // When
        let result = subject.buildURL(baseURL: baseURL, path: "v1/test")

        // Then
        #expect(result.absoluteString == "https://api.example.com/v1/test")
    }
}
