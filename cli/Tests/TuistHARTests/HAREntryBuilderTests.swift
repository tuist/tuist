import Foundation
import Testing

@testable import TuistHAR

struct HAREntryBuildingTests {
    @Test
    func recordRequest_createsCorrectEntry() async {
        // Given
        let recorder = HARRecorder(filePath: nil)
        let url = URL(string: "https://api.example.com/v1/test?key=value")!
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(0.5)
        let requestHeaders = [HAR.Header(name: "Content-Type", value: "application/json")]
        let responseHeaders = [HAR.Header(name: "Content-Type", value: "application/json")]
        let requestBody = "request body".data(using: .utf8)
        let responseBody = "response body".data(using: .utf8)

        // When
        await recorder.recordRequest(
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
        let entries = await recorder.getEntries()
        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.request.method == "POST")
        #expect(entry.request.url == "https://api.example.com/v1/test?key=value")
        #expect(entry.request.httpVersion == "HTTP/1.1")
        #expect(entry.response.status == 200)
        #expect(entry.response.statusText == "OK")
        #expect(entry.time == 500)
    }

    @Test
    func recordRequest_filtersSensitiveHeaders() async {
        // Given
        let recorder = HARRecorder(filePath: nil)
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
        await recorder.recordRequest(
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
        let entries = await recorder.getEntries()
        let entry = entries[0]

        let authHeader = entry.request.headers.first { $0.name == "Authorization" }
        #expect(authHeader?.value == "[REDACTED]")

        let cookieHeader = entry.response.headers.first { $0.name == "Set-Cookie" }
        #expect(cookieHeader?.value == "[REDACTED]")

        let contentTypeHeader = entry.request.headers.first { $0.name == "Content-Type" }
        #expect(contentTypeHeader?.value == "application/json")
    }

    @Test
    func recordRequest_extractsQueryParameters() async {
        // Given
        let recorder = HARRecorder(filePath: nil)
        let url = URL(string: "https://api.example.com/test?foo=bar&baz=qux")!
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(0.1)

        // When
        await recorder.recordRequest(
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
        let entries = await recorder.getEntries()
        let entry = entries[0]
        #expect(entry.request.queryString.count == 2)
        #expect(entry.request.queryString.contains { $0.name == "foo" && $0.value == "bar" })
        #expect(entry.request.queryString.contains { $0.name == "baz" && $0.value == "qux" })
    }

    @Test
    func recordError_createsCorrectEntry() async {
        // Given
        let recorder = HARRecorder(filePath: nil)
        let url = URL(string: "https://api.example.com/test")!
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(1.0)
        let error = NSError(domain: "TestError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Test error"])

        // When
        await recorder.recordError(
            url: url,
            method: "POST",
            requestHeaders: [],
            requestBody: nil,
            error: error,
            startTime: startTime,
            endTime: endTime
        )

        // Then
        let entries = await recorder.getEntries()
        let entry = entries[0]
        #expect(entry.request.method == "POST")
        #expect(entry.response.status == 0)
        #expect(entry.response.statusText == "Error")
        #expect(entry.response.content.mimeType == "text/plain")
        #expect(entry.response.content.text?.contains("TestError") == true)
        #expect(entry.time == 1000)
    }
}
