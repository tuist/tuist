#if os(macOS) && canImport(TuistHAR)
    import FileSystem
    import Foundation
    import Path
    import Synchronization
    import Testing

    @testable import TuistHTTP

    @Suite
    struct FileClientTests {
        @Test func download_moves_url_session_temporary_file_to_requested_destination() async throws {
            DownloadURLProtocol.responseData = Data("downloaded shard archive".utf8)
            DownloadURLProtocol.statusCode = 200

            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DownloadURLProtocol.self]
            let session = URLSession(configuration: configuration)
            let fileSystem = FileSystem()
            let subject = FileClient(session: session, fileSystem: fileSystem)
            let destinationDirectory = try await fileSystem.makeTemporaryDirectory(prefix: "file-client-download-test")
            let destinationPath = destinationDirectory.appending(component: "shared.aar")

            try await subject.download(
                url: URL(string: "https://tuist.dev/artifacts/shared.aar")!,
                to: destinationPath
            )

            #expect(try await fileSystem.readTextFile(at: destinationPath) == "downloaded shard archive")
        }

        @Test(arguments: [(404, false), (403, false), (503, true), (502, true)])
        func download_failure_carries_the_status_so_only_transient_ones_are_retried(
            statusCode: Int,
            retryable: Bool
        ) async throws {
            let fileSystem = FileSystem()
            let destinationDirectory = try await fileSystem.makeTemporaryDirectory(prefix: "file-client-download-test")
            let path = "/artifacts/\(UUID().uuidString).aar"
            StatusURLProtocol.statusCodes.withLock { $0[path] = statusCode }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StatusURLProtocol.self]
            let subject = FileClient(session: URLSession(configuration: configuration), fileSystem: fileSystem)

            let error = await #expect(throws: (any Error).self) {
                try await subject.download(
                    url: URL(string: "https://tuist.dev\(path)")!,
                    to: destinationDirectory.appending(component: "shared.aar")
                )
            }

            #expect((error as? any HTTPStatusCodeError)?.httpStatusCode == statusCode)
            #expect((error as? any HTTPStatusCodeError)?.isRetryable == retryable)
        }

        @Test(arguments: [("ETag", "\"v1\""), ("Last-Modified", "Mon, 16 Nov 2026 10:00:00 GMT")])
        func download_after_a_failed_attempt_requests_only_the_bytes_it_did_not_receive(
            validatorHeader: String,
            validator: String
        ) async throws {
            let body = Data("0123456789abcdef".utf8)
            let download = try await makeScriptedDownload(replies: [
                ScriptedReply(statusCode: 200, headers: [validatorHeader: validator], body: body.prefix(6), failsAfterBody: true),
                ScriptedReply(
                    statusCode: 206,
                    headers: [validatorHeader: validator, "Content-Range": "bytes 6-15/16"],
                    body: body.dropFirst(6)
                ),
            ])

            let error = await #expect(throws: (any Error).self) {
                try await download.subject.download(url: download.url, to: download.destination)
            }
            #expect(HTTPRetryPolicy.isRetryable(try #require(error)))
            try await download.subject.download(url: download.url, to: download.destination)

            let requests = ScriptedURLProtocol.requests(for: download.url)
            #expect(requests.map { $0["Range"] } == [nil, "bytes=6-"])
            #expect(requests.map { $0["If-Range"] } == [nil, validator])
            #expect(try Data(contentsOf: download.destination.url) == body)
            #expect(try await !FileSystem()
                .exists(download.destination.parentDirectory.appending(component: "shared.aar.partial")))
        }

        /// The server keeps only the first 240 characters of a command's error, so the progress has to come before the
        /// temporary path and the presigned URL.
        @Test func failed_attempts_lead_their_error_with_how_much_of_the_object_is_on_disk() async throws {
            let download = try await makeScriptedDownload(replies: [
                ScriptedReply(
                    statusCode: 200,
                    headers: ["ETag": "\"v1\"", "Content-Length": "4000000"],
                    body: Data(count: 1_500_000),
                    failsAfterBody: true
                ),
                ScriptedReply(
                    statusCode: 206,
                    headers: ["ETag": "\"v1\"", "Content-Range": "bytes 1500000-3999999/4000000"],
                    body: Data(count: 1_000_000),
                    failsAfterBody: true
                ),
            ])
            var descriptions: [String] = []
            for _ in 0 ..< 3 {
                let error = await #expect(throws: (any Error).self) {
                    try await download.subject.download(url: download.url, to: download.destination)
                }
                descriptions.append(String(describing: try #require(error)))
            }

            #expect(descriptions[0].hasPrefix("Received a session error after downloading 1.5 of 4.0 MB for file"))
            #expect(descriptions[1].hasPrefix(
                "Received a session error after downloading 2.5 of 4.0 MB (1.0 MB in this attempt) for file"
            ))
            #expect(descriptions[2].hasPrefix(
                "Received a session error after downloading 2.5 MB (0.0 MB in this attempt) for file"
            ))
        }

        @Test func download_replaces_the_received_bytes_when_the_server_answers_the_range_with_the_whole_object() async throws {
            let download = try await makeScriptedDownload(replies: [
                ScriptedReply(statusCode: 200, headers: ["ETag": "\"v1\""], body: Data("stale-".utf8), failsAfterBody: true),
                ScriptedReply(statusCode: 200, headers: ["ETag": "\"v2\""], body: Data("replaced object".utf8)),
            ])

            await #expect(throws: (any Error).self) {
                try await download.subject.download(url: download.url, to: download.destination)
            }
            try await download.subject.download(url: download.url, to: download.destination)

            #expect(ScriptedURLProtocol.requests(for: download.url).map { $0["Range"] } == [nil, "bytes=6-"])
            #expect(try String(contentsOf: download.destination.url, encoding: .utf8) == "replaced object")
        }

        @Test(arguments: [
            ScriptedReply(statusCode: 416, headers: ["Content-Range": "bytes */4"], body: Data()),
            ScriptedReply(statusCode: 206, headers: ["ETag": "\"v2\"", "Content-Range": "bytes 6-9/10"], body: Data("WXYZ".utf8)),
            ScriptedReply(statusCode: 206, headers: ["ETag": "\"v1\"", "Content-Range": "bytes 0-3/10"], body: Data("WXYZ".utf8)),
        ])
        func download_starts_over_when_the_range_response_does_not_continue_the_received_bytes(
            rangeReply: ScriptedReply
        ) async throws {
            let download = try await makeScriptedDownload(replies: [
                ScriptedReply(statusCode: 200, headers: ["ETag": "\"v1\""], body: Data("stale-".utf8), failsAfterBody: true),
                rangeReply,
                ScriptedReply(statusCode: 200, headers: ["ETag": "\"v2\""], body: Data("whole".utf8)),
            ])

            await #expect(throws: (any Error).self) {
                try await download.subject.download(url: download.url, to: download.destination)
            }
            try await download.subject.download(url: download.url, to: download.destination)

            #expect(ScriptedURLProtocol.requests(for: download.url).map { $0["Range"] } == [nil, "bytes=6-", nil])
            #expect(try String(contentsOf: download.destination.url, encoding: .utf8) == "whole")
        }

        @Test(arguments: [[:], ["ETag": "W/\"v1\""], ["ETag": "\"v1\"", "Content-Encoding": "gzip"]])
        func download_after_a_failed_attempt_starts_over_when_the_response_cannot_be_resumed(
            headers: [String: String]
        ) async throws {
            let download = try await makeScriptedDownload(replies: [
                ScriptedReply(statusCode: 200, headers: headers, body: Data("stale-".utf8), failsAfterBody: true),
                ScriptedReply(statusCode: 200, headers: [:], body: Data("whole".utf8)),
            ])

            await #expect(throws: (any Error).self) {
                try await download.subject.download(url: download.url, to: download.destination)
            }
            try await download.subject.download(url: download.url, to: download.destination)

            #expect(ScriptedURLProtocol.requests(for: download.url).map { $0["Range"] } == [nil, nil])
            #expect(try String(contentsOf: download.destination.url, encoding: .utf8) == "whole")
        }

        /// 1000 bytes in 100-byte probe: the other 900 split into 8 ranges of 113 bytes, the second at 213-325.
        @Test func parallel_download_retries_only_the_bytes_a_failed_range_did_not_receive() async throws {
            let body = Data((0 ..< 1000).map { UInt8(truncatingIfNeeded: $0 * 7) })
            let download = try await makeRangeDownload(
                object: RangeURLProtocol.Object(body: body, etag: "\"v1\"", failOnceAt: 213)
            )

            let error = await #expect(throws: (any Error).self) {
                try await download.subject.downloadInParallel(url: download.url, to: download.destination)
            }
            #expect(HTTPRetryPolicy.isRetryable(try #require(error)))
            let firstAttempt = RangeURLProtocol.requests(for: download.url).count
            try await download.subject.downloadInParallel(url: download.url, to: download.destination)

            let retried = RangeURLProtocol.requests(for: download.url).dropFirst(firstAttempt)
            // The failed range sent half of its 113 bytes (56) before failing.
            #expect(retried.map { $0["Range"] } == ["bytes=269-325"])
            #expect(retried.map { $0["If-Range"] } == ["\"v1\""])
            #expect(try Data(contentsOf: download.destination.url) == body)
        }

        @Test func parallel_download_falls_back_to_one_request_when_the_server_ignores_ranges() async throws {
            let body = Data((0 ..< 1000).map { UInt8(truncatingIfNeeded: $0) })
            let download = try await makeRangeDownload(
                object: RangeURLProtocol.Object(body: body, etag: "\"v1\"", honorsRanges: false)
            )

            try await download.subject.downloadInParallel(url: download.url, to: download.destination)

            #expect(RangeURLProtocol.requests(for: download.url).map { $0["Range"] } == ["bytes=0-99", nil])
            #expect(try Data(contentsOf: download.destination.url) == body)
        }

        @Test func parallel_download_starts_over_when_the_object_changed_between_attempts() async throws {
            let body = Data((0 ..< 1000).map { UInt8(truncatingIfNeeded: $0) })
            let download = try await makeRangeDownload(
                object: RangeURLProtocol.Object(body: body, etag: "\"v1\"", failOnceAt: 213)
            )
            await #expect(throws: (any Error).self) {
                try await download.subject.downloadInParallel(url: download.url, to: download.destination)
            }
            let replaced = Data((0 ..< 700).map { UInt8(truncatingIfNeeded: $0 * 3) })
            RangeURLProtocol.objects.withLock { $0[download.url.path]?.body = replaced; $0[download.url.path]?.etag = "\"v2\"" }

            try await download.subject.downloadInParallel(url: download.url, to: download.destination)

            #expect(try Data(contentsOf: download.destination.url) == replaced)
        }

        @Test func in_order_download_yields_the_object_in_order_when_a_middle_range_is_retried() async throws {
            let body = Data((0 ..< 1000).map { UInt8(truncatingIfNeeded: $0 * 13) })
            let download = try await makeRangeDownload(
                object: RangeURLProtocol.Object(body: body, etag: "\"v1\"", failOnceAt: 300)
            )

            // The range at 300 fails once and is retried after the later ranges have arrived.
            var received = Data()
            for try await chunk in download.subject.downloadInOrder(url: download.url) {
                received.append(chunk)
            }

            #expect(received == body)
            let ranges = RangeURLProtocol.requests(for: download.url).compactMap { $0["Range"] }
            #expect(ranges.filter { $0 == "bytes=300-399" }.count == 2)
            #expect(Set(ranges) == Set((0 ..< 10).map { "bytes=\($0 * 100)-\($0 * 100 + 99)" }))
        }

        @Test func in_order_download_reports_a_server_that_ignores_ranges_before_yielding_anything() async throws {
            let body = Data((0 ..< 1000).map { UInt8(truncatingIfNeeded: $0) })
            let download = try await makeRangeDownload(
                object: RangeURLProtocol.Object(body: body, etag: "\"v1\"", honorsRanges: false)
            )

            var received = 0
            await #expect(throws: OrderedDownloadError.rangesNotServed) {
                for try await chunk in download.subject.downloadInOrder(url: download.url) {
                    received += chunk.count
                }
            }

            #expect(received == 0)
            #expect(RangeURLProtocol.requests(for: download.url).map { $0["Range"] } == ["bytes=0-99"])
        }

        private func makeRangeDownload(object: RangeURLProtocol.Object) async throws -> ScriptedDownload {
            let fileSystem = FileSystem()
            let url = URL(string: "https://tuist.dev/artifacts/\(UUID().uuidString).aar")!
            RangeURLProtocol.objects.withLock { $0[url.path] = object }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [RangeURLProtocol.self]
            let destinationDirectory = try await fileSystem.makeTemporaryDirectory(prefix: "file-client-download-test")
            return ScriptedDownload(
                subject: FileClient(
                    session: URLSession(configuration: configuration), fileSystem: fileSystem, parallelRangeSize: 100
                ),
                url: url,
                destination: destinationDirectory.appending(component: "shared.aar")
            )
        }

        private struct ScriptedDownload {
            let subject: FileClient
            let url: URL
            let destination: AbsolutePath
        }

        private func makeScriptedDownload(replies: [ScriptedReply]) async throws -> ScriptedDownload {
            let fileSystem = FileSystem()
            let url = URL(string: "https://tuist.dev/artifacts/\(UUID().uuidString).aar")!
            ScriptedURLProtocol.scripts.withLock { $0[url.path] = (replies, []) }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ScriptedURLProtocol.self]
            let destinationDirectory = try await fileSystem.makeTemporaryDirectory(prefix: "file-client-download-test")
            return ScriptedDownload(
                subject: FileClient(session: URLSession(configuration: configuration), fileSystem: fileSystem),
                url: url,
                destination: destinationDirectory.appending(component: "shared.aar")
            )
        }
    }

    struct ScriptedReply: Sendable, CustomTestStringConvertible {
        var statusCode: Int
        var headers: [String: String]
        var body: Data
        /// Fails the transfer with a timeout after sending the body, as a stalled transfer does.
        var failsAfterBody = false

        var testDescription: String {
            "\(statusCode) \(headers)"
        }
    }

    /// Answers each request to a path with the next scripted reply and records the request headers.
    private final class ScriptedURLProtocol: URLProtocol {
        static let scripts = Mutex<[String: (replies: [ScriptedReply], requests: [[String: String]])]>([:])

        static func requests(for url: URL) -> [[String: String]] {
            scripts.withLock { $0[url.path]?.requests ?? [] }
        }

        override static func canInit(with _: URLRequest) -> Bool {
            true
        }

        override static func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let reply = Self.scripts.withLock { scripts -> ScriptedReply? in
                scripts[request.url!.path]?.requests.append(request.allHTTPHeaderFields ?? [:])
                guard scripts[request.url!.path]?.replies.isEmpty == false else { return nil }
                return scripts[request.url!.path]?.replies.removeFirst()
            }
            guard let reply else {
                client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
                return
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: reply.statusCode,
                httpVersion: "HTTP/1.1",
                // Without a content type, URLSession holds the response back to sniff the first 512 bytes, so a
                // transfer failing before then would never reach the delegate.
                headerFields: reply.headers.merging(["Content-Type": "application/octet-stream"]) { header, _ in header }
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            if reply.failsAfterBody {
                // URLSession drops a body still queued for the delegate when the failure follows at once, which a
                // stalled transfer, whose bytes arrived long before its timeout, never does.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [self] in
                    client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                }
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() {}
    }

    /// Serves byte ranges of an object, as S3 does, and records the request headers.
    private final class RangeURLProtocol: URLProtocol {
        struct Object {
            var body: Data
            var etag: String
            var honorsRanges = true
            /// Fails the first request for a range starting here after sending half of it.
            var failOnceAt: Int64?
            var requests: [[String: String]] = []
        }

        static let objects = Mutex<[String: Object]>([:])

        static func requests(for url: URL) -> [[String: String]] {
            objects.withLock { $0[url.path]?.requests ?? [] }
        }

        override static func canInit(with _: URLRequest) -> Bool {
            true
        }

        override static func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let path = request.url!.path
            let range = request.value(forHTTPHeaderField: "Range")
            let bounds = range.flatMap { range -> (Int, Int?)? in
                let parts = range.dropFirst("bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
                guard let start = Int(parts[0]) else { return nil }
                return (start, parts.count > 1 ? Int(parts[1]) : nil)
            }
            let (object, fails) = Self.objects.withLock { objects -> (Object, Bool) in
                objects[path]!.requests.append(request.allHTTPHeaderFields ?? [:])
                let fails = bounds != nil && bounds.map { Int64($0.0) } == objects[path]!.failOnceAt
                if fails { objects[path]!.failOnceAt = nil }
                return (objects[path]!, fails)
            }
            var headers = ["Content-Type": "application/octet-stream", "ETag": object.etag]
            let slice: Data
            let statusCode: Int
            if object.honorsRanges, let (start, end) = bounds {
                let last = min(end ?? object.body.count - 1, object.body.count - 1)
                slice = object.body.subdata(in: start ..< last + 1)
                statusCode = 206
                headers["Content-Range"] = "bytes \(start)-\(last)/\(object.body.count)"
            } else {
                slice = object.body
                statusCode = 200
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if fails {
                client?.urlProtocol(self, didLoad: slice.prefix(slice.count / 2))
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [self] in
                    client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                }
            } else {
                client?.urlProtocol(self, didLoad: slice)
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() {}
    }

    private final class StatusURLProtocol: URLProtocol {
        static let statusCodes = Mutex<[String: Int]>([:])

        override class func canInit(with _: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let statusCode = Self.statusCodes.withLock { $0[request.url!.path] ?? 200 }
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private final class DownloadURLProtocol: URLProtocol {
        nonisolated(unsafe) static var responseData = Data()
        nonisolated(unsafe) static var statusCode = 200

        override class func canInit(with _: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: Self.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.responseData)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }
#endif
