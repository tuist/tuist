#if os(macOS) && canImport(TuistHAR)
    import FileSystem
    import Foundation
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
