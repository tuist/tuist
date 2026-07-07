import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing

@testable import TuistServer

@Suite(.serialized)
struct MultipartUploadArtifactServiceTests {
    @Test(.inTemporaryDirectory)
    func multipartUploadArtifact_uploadsCompleteParts() async throws {
        MultipartUploadURLProtocol.reset()
        MultipartUploadURLProtocol.statusCode = 200

        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let artifactPath = temporaryDirectory.appending(component: "artifact.aar")
        let partSize = 10 * 1024 * 1024
        let payload = Data(repeating: 7, count: partSize + 7)
        try payload.write(to: URL(fileURLWithPath: artifactPath.pathString))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultipartUploadURLProtocol.self]
        let subject = MultipartUploadArtifactService(
            urlSession: URLSession(configuration: configuration),
            retryProvider: NoRetryProvider()
        )
        let partRecorder = MultipartUploadPartRecorder()

        let parts = try await subject.multipartUploadArtifact(
            artifactPath: artifactPath,
            generateUploadURL: { part in
                await partRecorder.record(part)
                return "https://tuist.dev/upload?partNumber=\(part.number)"
            },
            updateProgress: { _ in }
        )

        #expect(parts.map(\.partNumber) == [1, 2])
        #expect(parts.map(\.etag) == ["etag-1", "etag-2"])

        let generatedParts = await partRecorder.parts
        #expect(generatedParts.map(\.number) == [1, 2])
        #expect(generatedParts.map(\.contentLength) == [partSize, 7])

        let requests = MultipartUploadURLProtocol.requests.sorted(by: { $0.partNumber < $1.partNumber })
        #expect(requests.map(\.partNumber) == [1, 2])
        #expect(requests.map(\.contentLength) == [partSize, 7])
        #expect(requests[0].body.count == partSize)
        #expect(requests[1].body == Data(repeating: 7, count: 7))
    }

    @Test(.inTemporaryDirectory)
    func multipartUploadArtifact_rejectsNonSuccessfulUploadResponseWithEtag() async throws {
        MultipartUploadURLProtocol.reset()
        MultipartUploadURLProtocol.responseData = Data("storage error".utf8)
        MultipartUploadURLProtocol.statusCode = 500

        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let artifactPath = temporaryDirectory.appending(component: "artifact.aar")
        try Data("payload".utf8).write(to: URL(fileURLWithPath: artifactPath.pathString))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultipartUploadURLProtocol.self]
        let subject = MultipartUploadArtifactService(
            urlSession: URLSession(configuration: configuration),
            retryProvider: NoRetryProvider()
        )

        do {
            _ = try await subject.multipartUploadArtifact(
                artifactPath: artifactPath,
                generateUploadURL: { part in "https://tuist.dev/upload?partNumber=\(part.number)" },
                updateProgress: { _ in }
            )
            Issue.record("Expected multipart upload to reject the failed response")
        } catch let error as MultipartUploadArtifactServiceError {
            guard case let .uploadFailed(url, statusCode, body) = error else {
                Issue.record("Expected uploadFailed, got \(error)")
                return
            }
            #expect(url?.absoluteString == "https://tuist.dev/upload?partNumber=1")
            #expect(statusCode == 500)
            #expect(body == "storage error")
        }
    }

    @Test(.inTemporaryDirectory)
    func multipartUploadArtifact_retriesWhenArtifactChangesWhileUploading() async throws {
        MultipartUploadURLProtocol.reset()
        MultipartUploadURLProtocol.statusCode = 200

        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let artifactPath = temporaryDirectory.appending(component: "artifact.aar")
        let initialPayload = Data("initial".utf8)
        let appendedPayload = Data("-appended".utf8)
        var expectedPayload = initialPayload
        expectedPayload.append(appendedPayload)
        try initialPayload.write(to: URL(fileURLWithPath: artifactPath.pathString))

        let lock = NSLock()
        var didAppend = false
        MultipartUploadURLProtocol.onRequest = { _, _ in
            lock.lock()
            defer { lock.unlock() }
            guard !didAppend else { return }
            didAppend = true

            guard let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: artifactPath.pathString)) else {
                return
            }
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: appendedPayload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultipartUploadURLProtocol.self]
        let subject = MultipartUploadArtifactService(
            urlSession: URLSession(configuration: configuration),
            retryProvider: NoRetryProvider()
        )

        let parts = try await subject.multipartUploadArtifact(
            artifactPath: artifactPath,
            generateUploadURL: { part in "https://tuist.dev/upload?partNumber=\(part.number)" },
            updateProgress: { _ in }
        )

        #expect(parts.map(\.partNumber) == [1])
        #expect(parts.map(\.etag) == ["etag-1"])

        let requests = MultipartUploadURLProtocol.requests
        #expect(requests.map(\.body) == [initialPayload, expectedPayload])
    }
}

private actor MultipartUploadPartRecorder {
    private(set) var parts: [MultipartUploadArtifactPart] = []

    func record(_ part: MultipartUploadArtifactPart) {
        parts.append(part)
    }
}

private struct NoRetryProvider: RetryProviding {
    func runWithRetries<T>(
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await operation()
    }
}

private struct CapturedMultipartUploadRequest {
    let partNumber: Int
    let contentLength: Int
    let body: Data
}

private final class MultipartUploadURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var onRequest: ((URLRequest, Data) -> Void)?

    private nonisolated(unsafe) static var capturedRequests: [CapturedMultipartUploadRequest] = []
    private nonisolated(unsafe) static let lock = NSLock()

    static var requests: [CapturedMultipartUploadRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        capturedRequests = []
        responseData = Data()
        statusCode = 200
        onRequest = nil
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = Self.bodyData(from: request)
        Self.onRequest?(request, body)
        let partNumber = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?
            .first(where: { $0.name == "partNumber" })?
            .value
            .flatMap(Int.init) ?? 0

        Self.lock.lock()
        Self.capturedRequests.append(
            CapturedMultipartUploadRequest(
                partNumber: partNumber,
                contentLength: Int(request.value(forHTTPHeaderField: "Content-Length") ?? "") ?? 0,
                body: body
            )
        )
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Etag": "etag-\(partNumber)"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            guard bytesRead > 0 else { break }
            data.append(buffer, count: bytesRead)
        }
        return data
    }
}
