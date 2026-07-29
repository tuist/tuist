import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing

@testable import TuistHAR

struct HARRecorderTests {
    // MARK: - Entry Building Tests

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

    // MARK: - Persistence Tests

    @Test(.inTemporaryDirectory)
    func record_appendsEntryToLog() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let harFilePath = temporaryDirectory.appending(component: "network.har")

        // Given
        let recorder = HARRecorder(filePath: harFilePath)
        let entry = makeTestEntry()

        // When
        await recorder.record(entry)

        // Then
        let entries = await recorder.getEntries()
        #expect(entries.count == 1)
        #expect(entries[0].request.url == "https://api.example.com/test")
    }

    @Test(.inTemporaryDirectory)
    func finish_persistsToFile() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let harFilePath = temporaryDirectory.appending(component: "network.har")

        // Given
        let recorder = HARRecorder(filePath: harFilePath)
        let entry = makeTestEntry()

        // When
        await recorder.record(entry)
        await recorder.finish()

        // Then
        let fileSystem = FileSystem()
        #expect(try await fileSystem.exists(harFilePath))

        let data = try Data(contentsOf: URL(fileURLWithPath: harFilePath.pathString))
        let log = try HAR.decode(from: data)
        #expect(log.entries.count == 1)
    }

    @Test(.inTemporaryDirectory)
    func finishCurrent_persistsActiveRecorderBeforeTaskLocalScopeExits() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let harFilePath = temporaryDirectory.appending(component: "network.har")

        let recorder = HARRecorder(filePath: harFilePath)

        try await HARRecorder.withCurrent(recorder) {
            await recorder.record(makeTestEntry())
            await HARRecorder.finishCurrent()

            let fileSystem = FileSystem()
            #expect(try await fileSystem.exists(harFilePath))

            let data = try Data(contentsOf: URL(fileURLWithPath: harFilePath.pathString))
            let log = try HAR.decode(from: data)
            #expect(log.entries.count == 1)
        }
    }

    @Test
    func finish_ignoresEntriesRecordedAfterFinishing() async {
        // Given
        let recorder = HARRecorder(filePath: nil)

        // When
        await recorder.finish()
        await recorder.record(makeTestEntry())

        // Then
        let entries = await recorder.getEntries()
        #expect(entries.isEmpty)
    }

    @Test
    func record_handlesConcurrentEntries() async {
        // Given
        let recorder = HARRecorder(filePath: nil)
        let entryCount = 500

        // When
        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< entryCount {
                group.addTask {
                    await recorder.record(Self.makeConcurrentEntry(index: index))
                }
            }
        }

        // Then
        let entries = await recorder.getEntries()
        #expect(entries.count == entryCount)
    }

    @Test
    func finish_ignoresDetachedEntriesThatResumeAfterFinishing() async throws {
        // Given
        let recorder = HARRecorder(filePath: nil)
        let gate = Gate()

        // When
        for index in 0 ..< 100 {
            recorder.recordDetached { recorder in
                await gate.wait()
                await recorder.record(Self.makeConcurrentEntry(index: index))
            }
        }
        await recorder.finish()
        await gate.open()

        try await Task.sleep(nanoseconds: 10_000_000)

        // Then
        let entries = await recorder.getEntries()
        #expect(entries.isEmpty)
    }

    @Test
    func record_withoutFilePath_doesNotPersist() async throws {
        // Given
        let recorder = HARRecorder(filePath: nil)
        let entry = makeTestEntry()

        // When
        await recorder.record(entry)

        // Then
        let entries = await recorder.getEntries()
        #expect(entries.count == 1)
    }

    @Test
    func filterSensitiveHeaders_redactsSensitiveHeaders() {
        // Given
        let headers = [
            HAR.Header(name: "Authorization", value: "Bearer secret-token"),
            HAR.Header(name: "Content-Type", value: "application/json"),
            HAR.Header(name: "Cookie", value: "session=abc123"),
            HAR.Header(name: "Accept", value: "*/*"),
            HAR.Header(name: "X-Api-Key", value: "my-api-key"),
        ]

        // When
        let filtered = HARRecorder.filterSensitiveHeaders(headers)

        // Then
        #expect(filtered[0].value == "[REDACTED]")
        #expect(filtered[1].value == "application/json")
        #expect(filtered[2].value == "[REDACTED]")
        #expect(filtered[3].value == "*/*")
        #expect(filtered[4].value == "[REDACTED]")
    }

    private actor Gate {
        private var isOpen = false
        private var continuations: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }

            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }

        func open() {
            isOpen = true
            let continuations = continuations
            self.continuations.removeAll()
            continuations.forEach { $0.resume() }
        }
    }

    private static func makeConcurrentEntry(index: Int) -> HAR.Entry {
        HAR.Entry(
            startedDateTime: Date(),
            time: 100,
            request: HAR.Request(
                method: "GET",
                url: "https://api.example.com/test/\(index)"
            ),
            response: HAR.Response(
                status: 200,
                statusText: "OK",
                content: HAR.Content(
                    size: 10,
                    mimeType: "application/json",
                    text: "{}"
                )
            ),
            timings: HAR.Timings(
                send: 0,
                wait: 100,
                receive: 0
            )
        )
    }

    private func makeTestEntry() -> HAR.Entry {
        HAR.Entry(
            startedDateTime: Date(),
            time: 100,
            request: HAR.Request(
                method: "GET",
                url: "https://api.example.com/test"
            ),
            response: HAR.Response(
                status: 200,
                statusText: "OK",
                content: HAR.Content(
                    size: 10,
                    mimeType: "application/json",
                    text: "{}"
                )
            ),
            timings: HAR.Timings(
                send: 0,
                wait: 100,
                receive: 0
            )
        )
    }
}
