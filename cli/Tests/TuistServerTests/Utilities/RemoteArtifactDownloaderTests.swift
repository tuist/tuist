import FileSystem
import Foundation
import Path
import Testing
import TuistHTTP

@testable import TuistServer

@Suite(.serialized)
struct RemoteArtifactDownloaderTests {
    private let fileSystem = FileSystem()
    private let url = URL(string: "https://storage.tuist.dev/artifacts/preview.zip")!

    private func makeSubject(chunkByteCount: Int64) -> RemoteArtifactDownloader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArtifactURLProtocol.self]
        return RemoteArtifactDownloader(
            urlSession: URLSession(configuration: configuration),
            retryProvider: RetryProvider(maximumRetryCount: 3, delayProvider: NoDelayProvider()),
            chunkByteCount: chunkByteCount
        )
    }

    @Test func download_resumes_from_the_last_received_byte_when_the_connection_drops() async throws {
        let payload = Data((0 ..< 5000).map { UInt8($0 % 251) })
        ArtifactURLProtocol.reset(payload: payload)
        ArtifactURLProtocol.failRequestsStartingAt = [2000]

        let downloaded = try #require(try await makeSubject(chunkByteCount: 1000).download(url: url))

        #expect(try Data(contentsOf: downloaded.url) == payload)
        #expect(
            ArtifactURLProtocol.requestedRanges == [
                "bytes=0-999",
                "bytes=1000-1999",
                "bytes=2000-2999",
                "bytes=2000-2999",
                "bytes=3000-3999",
                "bytes=4000-4999",
            ]
        )
    }

    @Test func download_sends_the_validator_of_the_first_response_on_subsequent_requests() async throws {
        ArtifactURLProtocol.reset(payload: Data(repeating: 7, count: 2500))

        _ = try await makeSubject(chunkByteCount: 1000).download(url: url)

        #expect(ArtifactURLProtocol.requestedValidators == [nil, "\"artifact-etag\"", "\"artifact-etag\""])
    }

    @Test func download_reports_progress_up_to_the_total_size() async throws {
        ArtifactURLProtocol.reset(payload: Data(repeating: 1, count: 2500))
        let subject = makeSubject(chunkByteCount: 1000)
        let (progressUpdates, continuation) = AsyncStream<RemoteArtifactDownloadProgress>.makeStream()

        async let downloaded = subject.download(url: url, progress: continuation)
        var recorded: [RemoteArtifactDownloadProgress] = []
        for await progress in progressUpdates {
            recorded.append(progress)
        }
        _ = try await downloaded

        #expect(
            recorded == [
                RemoteArtifactDownloadProgress(downloadedBytes: 1000, totalBytes: 2500),
                RemoteArtifactDownloadProgress(downloadedBytes: 2000, totalBytes: 2500),
                RemoteArtifactDownloadProgress(downloadedBytes: 2500, totalBytes: 2500),
            ]
        )
    }

    @Test func download_finishes_the_progress_stream_when_the_download_fails() async throws {
        ArtifactURLProtocol.reset(payload: Data())
        ArtifactURLProtocol.statusCode = 403
        let subject = makeSubject(chunkByteCount: 1000)
        let (progressUpdates, continuation) = AsyncStream<RemoteArtifactDownloadProgress>.makeStream()

        let downloaded = Task { try await subject.download(url: url, progress: continuation) }
        for await _ in progressUpdates {}

        await #expect(throws: RemoteArtifactDownloadStatusCodeError(url: url, httpStatusCode: 403)) {
            try await downloaded.value
        }
    }

    @Test func download_returns_the_whole_artifact_when_the_server_ignores_ranges() async throws {
        let payload = Data((0 ..< 4000).map { UInt8($0 % 251) })
        ArtifactURLProtocol.reset(payload: payload)
        ArtifactURLProtocol.supportsRanges = false

        let downloaded = try #require(try await makeSubject(chunkByteCount: 1000).download(url: url))

        #expect(try Data(contentsOf: downloaded.url) == payload)
        #expect(ArtifactURLProtocol.requestedRanges.count == 1)
    }

    @Test func download_returns_nil_when_the_artifact_is_not_found() async throws {
        ArtifactURLProtocol.reset(payload: Data())
        ArtifactURLProtocol.statusCode = 404

        #expect(try await makeSubject(chunkByteCount: 1000).download(url: url) == nil)
    }

    @Test func download_does_not_retry_a_permanent_client_error() async throws {
        ArtifactURLProtocol.reset(payload: Data())
        ArtifactURLProtocol.statusCode = 403

        await #expect(throws: RemoteArtifactDownloadStatusCodeError(url: url, httpStatusCode: 403)) {
            try await makeSubject(chunkByteCount: 1000).download(url: url)
        }
        #expect(ArtifactURLProtocol.requestedRanges.count == 1)
    }
}

private struct NoDelayProvider: DelayProviding {
    func delay(for _: Int) -> UInt64 { 0 }
}

private final class ArtifactURLProtocol: URLProtocol {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var supportsRanges = true
    nonisolated(unsafe) static var failRequestsStartingAt: Set<Int> = []
    nonisolated(unsafe) static var requestedRanges: [String] = []
    nonisolated(unsafe) static var requestedValidators: [String?] = []

    static func reset(payload: Data) {
        self.payload = payload
        statusCode = 200
        supportsRanges = true
        failRequestsStartingAt = []
        requestedRanges = []
        requestedValidators = []
    }

    override class func canInit(with _: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let rangeHeader = request.value(forHTTPHeaderField: "Range")
        Self.requestedRanges.append(rangeHeader ?? "")
        Self.requestedValidators.append(request.value(forHTTPHeaderField: "If-Range"))

        guard Self.statusCode == 200 else {
            respond(statusCode: Self.statusCode, body: Data(), headerFields: [:])
            return
        }

        let start = rangeHeader.flatMap(Self.start(ofRange:)) ?? 0
        if Self.failRequestsStartingAt.contains(start) {
            Self.failRequestsStartingAt.remove(start)
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }

        guard Self.supportsRanges, let rangeHeader, let requested = Self.range(of: rangeHeader) else {
            respond(statusCode: 200, body: Self.payload, headerFields: ["ETag": "\"artifact-etag\""])
            return
        }

        let end = min(requested.upperBound, Self.payload.count - 1)
        let body = Self.payload.subdata(in: requested.lowerBound ..< (end + 1))
        respond(
            statusCode: 206,
            body: body,
            headerFields: [
                "ETag": "\"artifact-etag\"",
                "Content-Range": "bytes \(requested.lowerBound)-\(end)/\(Self.payload.count)",
            ]
        )
    }

    override func stopLoading() {}

    private func respond(statusCode: Int, body: Data, headerFields: [String: String]) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headerFields
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func start(ofRange header: String) -> Int? {
        range(of: header)?.lowerBound
    }

    private static func range(of header: String) -> ClosedRange<Int>? {
        guard header.hasPrefix("bytes=") else { return nil }
        let bounds = header.dropFirst("bytes=".count).split(separator: "-")
        guard bounds.count == 2, let start = Int(bounds[0]), let end = Int(bounds[1]), start <= end else { return nil }
        return start ... end
    }
}
