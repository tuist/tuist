import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import TuistCore

@testable import TuistCache

struct CacheClientMetadataMiddlewareTests {
    private let subject = CacheClientMetadataMiddleware()

    @Test func intercept_adds_run_id_header() async throws {
        // Given
        let runMetadataStorage = RunMetadataStorage()
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let expectedResponse = HTTPResponse(status: 200)
        var capturedRequest: HTTPRequest!

        // When
        let (response, _) = try await RunMetadataStorage.$current.withValue(runMetadataStorage) {
            try await subject.intercept(
                request,
                body: nil,
                baseURL: URL(string: "https://cache.tuist.dev")!,
                operationID: "test"
            ) { request, body, _ in
                capturedRequest = request
                return (expectedResponse, body)
            }
        }

        // Then
        #expect(response == expectedResponse)
        let runIdHeader = capturedRequest.headerFields.first { $0.name.rawName == "x-tuist-run-id" }
        #expect(runIdHeader != nil)
        #expect(runIdHeader?.value == await runMetadataStorage.runId)
    }

    @Test func intercept_passes_request_to_next() async throws {
        // Given
        let request = HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/upload")
        let expectedBody: HTTPBody? = nil
        let expectedBaseURL = URL(string: "https://cache.tuist.dev")!
        var capturedBaseURL: URL!

        // When
        _ = try await subject.intercept(
            request,
            body: expectedBody,
            baseURL: expectedBaseURL,
            operationID: "test"
        ) { _, body, baseURL in
            capturedBaseURL = baseURL
            return (HTTPResponse(status: 200), body)
        }

        // Then
        #expect(capturedBaseURL == expectedBaseURL)
    }
}
