#if os(macOS)
    import Foundation
    import Path
    import Testing
    import TuistTesting
    @testable import TuistPlugin

    struct PluginServiceReleaseDownloadTests {
        private let fileClient = MockFileClient()
        private let releaseURL = URL(string: "https://github.com/acme/plugin/releases/download/1.0.0/Plugin.tuist-plugin.zip")!

        @Test func downloads_a_release_again_after_a_transient_failure() async throws {
            fileClient.stubbedDownloadErrors = [
                URLError(.networkConnectionLost),
                MockHTTPStatusCodeError(httpStatusCode: 503),
            ]

            try await PluginService(fileClient: fileClient)
                .downloadRelease(from: releaseURL, to: try AbsolutePath(validating: "/tmp/release.zip"))

            #expect(fileClient.invokedDownloadCount == 3)
        }

        @Test(arguments: [403, 404])
        func does_not_download_a_release_the_server_rejected_again(statusCode: Int) async throws {
            fileClient.stubbedDownloadErrors = [MockHTTPStatusCodeError(httpStatusCode: statusCode)]

            await #expect(throws: MockHTTPStatusCodeError(httpStatusCode: statusCode)) {
                try await PluginService(fileClient: fileClient)
                    .downloadRelease(from: releaseURL, to: try AbsolutePath(validating: "/tmp/release.zip"))
            }

            #expect(fileClient.invokedDownloadCount == 1)
        }
    }
#endif
