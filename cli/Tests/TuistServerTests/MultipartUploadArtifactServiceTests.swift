import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing

@testable import TuistServer

struct MultipartUploadArtifactServiceTests {
    @Test(.inTemporaryDirectory)
    func multipartUploadArtifact_uploadsCompleteParts() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let artifactPath = temporaryDirectory.appending(component: "artifact.aar")
        let partSize = 10 * 1024 * 1024
        let payload = Data(repeating: 7, count: partSize + 7)
        try payload.write(to: URL(fileURLWithPath: artifactPath.pathString))

        let uploadServer = MultipartUploadURLProtocolServer()
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
                return uploadServer.uploadURL(partNumber: part.number)
            },
            updateProgress: { _ in }
        )

        #expect(parts.map(\.partNumber) == [1, 2])
        #expect(parts.map(\.etag) == ["etag-1", "etag-2"])

        let generatedParts = await partRecorder.parts
        #expect(generatedParts.map(\.number) == [1, 2])
        #expect(generatedParts.map(\.contentLength) == [partSize, 7])

        let requests = uploadServer.requests.sorted(by: { $0.partNumber < $1.partNumber })
        #expect(requests.map(\.partNumber) == [1, 2])
        #expect(requests.map(\.contentLength) == [partSize, 7])
        #expect(requests[0].body.count == partSize)
        #expect(requests[1].body == Data(repeating: 7, count: 7))
    }

    @Test(.inTemporaryDirectory)
    func multipartUploadArtifact_rejectsNonSuccessfulUploadResponseWithEtag() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let artifactPath = temporaryDirectory.appending(component: "artifact.aar")
        try Data("payload".utf8).write(to: URL(fileURLWithPath: artifactPath.pathString))

        let uploadServer = MultipartUploadURLProtocolServer(
            responseData: Data("storage error".utf8),
            statusCode: 500
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultipartUploadURLProtocol.self]
        let subject = MultipartUploadArtifactService(
            urlSession: URLSession(configuration: configuration),
            retryProvider: NoRetryProvider()
        )
        let uploadURL = uploadServer.uploadURL(partNumber: 1)

        do {
            _ = try await subject.multipartUploadArtifact(
                artifactPath: artifactPath,
                generateUploadURL: { _ in uploadURL },
                updateProgress: { _ in }
            )
            Issue.record("Expected multipart upload to reject the failed response")
        } catch let error as MultipartUploadArtifactServiceError {
            guard case let .uploadFailed(url, statusCode, body) = error else {
                Issue.record("Expected uploadFailed, got \(error)")
                return
            }
            #expect(url?.absoluteString == uploadURL)
            #expect(statusCode == 500)
            #expect(body == "storage error")
        }
    }

    @Test(.inTemporaryDirectory)
    func multipartUploadArtifact_rejectsArtifactChangesWhileUploading() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let artifactPath = temporaryDirectory.appending(component: "artifact.aar")
        let initialPayload = Data("initial".utf8)
        let appendedPayload = Data("-appended".utf8)
        var expectedPayload = initialPayload
        expectedPayload.append(appendedPayload)
        try initialPayload.write(to: URL(fileURLWithPath: artifactPath.pathString))

        let lock = NSLock()
        var didAppend = false
        let uploadServer = MultipartUploadURLProtocolServer { _, _ in
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

        do {
            _ = try await subject.multipartUploadArtifact(
                artifactPath: artifactPath,
                generateUploadURL: { part in uploadServer.uploadURL(partNumber: part.number) },
                updateProgress: { _ in }
            )
            Issue.record("Expected multipart upload to reject the changing artifact")
        } catch let error as MultipartUploadArtifactServiceError {
            guard case let .incompleteArtifactRead(_, expectedBytes, readBytes) = error else {
                Issue.record("Expected incompleteArtifactRead, got \(error)")
                return
            }
            #expect(expectedBytes == UInt64(expectedPayload.count))
            #expect(readBytes == UInt64(initialPayload.count))
        }

        let requests = uploadServer.requests
        #expect(requests.map(\.body) == [initialPayload])
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

private final class MultipartUploadURLProtocolServer: @unchecked Sendable {
    private let id = UUID().uuidString

    init(
        responseData: Data = Data(),
        statusCode: Int = 200,
        onRequest: ((URLRequest, Data) -> Void)? = nil
    ) {
        MultipartUploadURLProtocol.register(
            id: id,
            responseData: responseData,
            statusCode: statusCode,
            onRequest: onRequest
        )
    }

    convenience init(onRequest: @escaping (URLRequest, Data) -> Void) {
        self.init(responseData: Data(), statusCode: 200, onRequest: onRequest)
    }

    deinit {
        MultipartUploadURLProtocol.unregister(id: id)
    }

    var requests: [CapturedMultipartUploadRequest] {
        MultipartUploadURLProtocol.requests(for: id)
    }

    func uploadURL(partNumber: Int) -> String {
        "https://tuist.dev/upload?testID=\(id)&partNumber=\(partNumber)"
    }
}

private struct MultipartUploadURLProtocolState {
    var responseData: Data
    var statusCode: Int
    var onRequest: ((URLRequest, Data) -> Void)?
    var capturedRequests: [CapturedMultipartUploadRequest]
}

private final class MultipartUploadURLProtocol: URLProtocol {
    private nonisolated(unsafe) static var states: [String: MultipartUploadURLProtocolState] = [:]
    private nonisolated(unsafe) static let lock = NSLock()

    static func register(
        id: String,
        responseData: Data,
        statusCode: Int,
        onRequest: ((URLRequest, Data) -> Void)?
    ) {
        lock.lock()
        defer { lock.unlock() }
        states[id] = MultipartUploadURLProtocolState(
            responseData: responseData,
            statusCode: statusCode,
            onRequest: onRequest,
            capturedRequests: []
        )
    }

    static func unregister(id: String) {
        lock.lock()
        defer { lock.unlock() }
        states[id] = nil
    }

    static func requests(for id: String) -> [CapturedMultipartUploadRequest] {
        lock.lock()
        defer { lock.unlock() }
        return states[id]?.capturedRequests ?? []
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = Self.bodyData(from: request)
        let testID = Self.queryItem(named: "testID", in: request.url)
        let state = Self.state(for: testID)
        state.onRequest?(request, body)

        let partNumber = Self.queryItem(named: "partNumber", in: request.url).flatMap(Int.init) ?? 0
        Self.recordRequest(testID: testID, request: request, body: body, partNumber: partNumber)

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: state.statusCode,
            httpVersion: nil,
            headerFields: ["Etag": "etag-\(partNumber)"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: state.responseData)
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

    private static func state(for testID: String?) -> MultipartUploadURLProtocolState {
        lock.lock()
        defer { lock.unlock() }
        guard let testID, let state = states[testID] else {
            return MultipartUploadURLProtocolState(
                responseData: Data(),
                statusCode: 200,
                onRequest: nil,
                capturedRequests: []
            )
        }
        return state
    }

    private static func recordRequest(
        testID: String?,
        request: URLRequest,
        body: Data,
        partNumber: Int
    ) {
        guard let testID else { return }

        lock.lock()
        defer { lock.unlock() }
        states[testID]?.capturedRequests.append(
            CapturedMultipartUploadRequest(
                partNumber: partNumber,
                contentLength: Int(request.value(forHTTPHeaderField: "Content-Length") ?? "") ?? 0,
                body: body
            )
        )
    }

    private static func queryItem(named name: String, in url: URL?) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}
