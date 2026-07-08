#if os(macOS) && canImport(TuistHAR)
    import FileSystem
    import Foundation
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
