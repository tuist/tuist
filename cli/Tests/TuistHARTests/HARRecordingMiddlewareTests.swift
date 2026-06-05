import FileSystem
import FileSystemTesting
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Path
import Testing

@testable import TuistHAR

struct HARRecordingMiddlewareTests {
    @Test(.inTemporaryDirectory)
    func intercept_recordsResponseInDetachedTask() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let harFilePath = temporaryDirectory.appending(component: "network.har")
        let recorder = HARRecorder(filePath: harFilePath)
        let subject = HARRecordingMiddleware()
        var request = HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/v1/projects?filter=owned")
        request.headerFields[.contentType] = "application/json"
        let responseBody = Data(#"{"ok":true}"#.utf8)

        try await HARRecorder.$current.withValue(recorder) {
            let (response, bodyForNext) = try await subject.intercept(
                request,
                body: HTTPBody(Data(#"{"name":"tuist"}"#.utf8)),
                baseURL: URL(string: "https://api.example.com")!,
                operationID: "createProject"
            ) { _, _, _ in
                var response = HTTPResponse(status: 201)
                response.headerFields[.contentType] = "application/json"
                return (response, HTTPBody(responseBody))
            }

            #expect(response.status.code == 201)
            let body = try #require(bodyForNext)
            let bodyData = try await Data(collecting: body, upTo: responseBody.count)
            #expect(bodyData == responseBody)

            let entries = try await waitForEntries(recorder, count: 1)
            #expect(entries.count == 1)
            #expect(entries[0].request.method == "POST")
            #expect(entries[0].request.url == "https://api.example.com/v1/projects?filter=owned")
            #expect(entries[0].response.status == 201)

            await recorder.finish()
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: harFilePath.pathString))
        let log = try HAR.decode(from: data)
        #expect(log.entries.count == 1)
    }

    @Test
    func intercept_recordsErrorBeforeThrowing() async throws {
        struct TestError: Error {}

        let recorder = HARRecorder(filePath: nil)
        let subject = HARRecordingMiddleware()
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/v1/projects")

        await #expect(throws: TestError.self) {
            try await HARRecorder.$current.withValue(recorder) {
                try await subject.intercept(
                    request,
                    body: nil,
                    baseURL: URL(string: "https://api.example.com")!,
                    operationID: "listProjects"
                ) { _, _, _ in
                    throw TestError()
                }
            }
        }

        let entries = try await waitForEntries(recorder, count: 1)
        #expect(entries.count == 1)
        #expect(entries[0].request.method == "GET")
        #expect(entries[0].request.url == "https://api.example.com/v1/projects")
        #expect(entries[0].response.status == 0)
    }

    private func waitForEntries(_ recorder: HARRecorder, count: Int) async throws -> [HAR.Entry] {
        for _ in 0 ..< 100 {
            let entries = await recorder.getEntries()
            if entries.count >= count {
                return entries
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return await recorder.getEntries()
    }
}
