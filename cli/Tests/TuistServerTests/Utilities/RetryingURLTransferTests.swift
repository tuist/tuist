#if os(macOS)
    import FileSystem
    import FileSystemTesting
    import Foundation
    import HTTPTypes
    import OpenAPIRuntime
    import Path
    import Synchronization
    import Testing
    import TuistEnvironment
    import TuistTesting

    @testable import TuistServer

    struct RetryingURLTransferTests {
        @Test(
            .withMockedEnvironment(),
            .inTemporaryDirectory,
            arguments: [StorageStep.dropConnection, .status(503)]
        )
        func coverage_upload_is_sent_again_after_a_transient_failure(failure: StorageStep) async throws {
            try mockEnvironment()
            let file = try await coverageFile()
            let url = ScriptedStorage.script([failure, .status(200)])

            try await CoverageFileUploader(urlSession: ScriptedStorage.session).upload(file: file, to: url)

            #expect(ScriptedStorage.attempts(url) == 2)
            #expect(ScriptedStorage.bodies(url) == [Data("coverage".utf8), Data("coverage".utf8)])
        }

        @Test(.withMockedEnvironment(), .inTemporaryDirectory)
        func coverage_upload_rejected_by_storage_is_not_sent_again() async throws {
            try mockEnvironment()
            let file = try await coverageFile()
            let url = ScriptedStorage.script([.status(403), .status(200)])

            let error = await #expect(throws: (any Error).self) {
                try await CoverageFileUploader(urlSession: ScriptedStorage.session).upload(file: file, to: url)
            }

            #expect(error?.localizedDescription == "The coverage upload was rejected with status 403.")
            #expect(ScriptedStorage.attempts(url) == 1)
        }

        @Test(.withMockedEnvironment(), .inTemporaryDirectory)
        func coverage_upload_reports_the_last_status_once_retries_run_out() async throws {
            try mockEnvironment()
            let file = try await coverageFile()
            let url = ScriptedStorage.script(Array(repeating: .status(503), count: 10))

            let error = await #expect(throws: (any Error).self) {
                try await CoverageFileUploader(urlSession: ScriptedStorage.session).upload(file: file, to: url)
            }

            #expect(error?.localizedDescription == "The coverage upload was rejected with status 503.")
            #expect(ScriptedStorage.attempts(url) == 4)
        }

        @Test(.withMockedEnvironment(), arguments: [StorageStep.dropConnection, .status(503)])
        func artifact_download_is_sent_again_after_a_transient_failure(failure: StorageStep) async throws {
            try mockEnvironment()
            let url = ScriptedStorage.script([failure, .status(200, body: Data("preview".utf8))])

            let path = try await RemoteArtifactDownloader(urlSession: ScriptedStorage.session).download(url: url)

            let downloaded = try #require(path)
            #expect(try await FileSystem().readTextFile(at: downloaded) == "preview")
            #expect(ScriptedStorage.attempts(url) == 2)
        }

        @Test(.withMockedEnvironment())
        func missing_artifact_is_not_downloaded_again() async throws {
            try mockEnvironment()
            let url = ScriptedStorage.script([.status(404), .status(200)])

            let path = try await RemoteArtifactDownloader(urlSession: ScriptedStorage.session).download(url: url)

            #expect(path == nil)
            #expect(ScriptedStorage.attempts(url) == 1)
        }

        @Test(.withMockedEnvironment())
        func forbidden_artifact_is_not_downloaded_again() async throws {
            try mockEnvironment()
            let url = ScriptedStorage.script([.status(403), .status(200)])

            await #expect(throws: RemoteArtifactDownloaderError.self) {
                try await RemoteArtifactDownloader(urlSession: ScriptedStorage.session).download(url: url)
            }

            #expect(ScriptedStorage.attempts(url) == 1)
        }

        @Test(.withMockedEnvironment(), .inTemporaryDirectory, arguments: [StorageStep.dropConnection, .status(503)])
        func attachment_upload_is_sent_again_after_a_transient_failure(failure: StorageStep) async throws {
            try mockEnvironment()
            let url = ScriptedStorage.script([failure, .status(200)])

            let id = try await createAttachment(uploadURL: url)

            #expect(id == "attachment-id")
            #expect(ScriptedStorage.attempts(url) == 2)
            #expect(ScriptedStorage.bodies(url) == [Data("attachment".utf8), Data("attachment".utf8)])
        }

        @Test(.withMockedEnvironment(), .inTemporaryDirectory, arguments: [403, 404])
        func attachment_upload_rejected_by_storage_is_not_sent_again(statusCode: Int) async throws {
            try mockEnvironment()
            let url = ScriptedStorage.script([.status(statusCode), .status(200)])

            let error = await #expect(throws: (any Error).self) {
                try await createAttachment(uploadURL: url)
            }

            #expect(error?.localizedDescription == "The attachment upload to storage failed.")
            #expect(ScriptedStorage.attempts(url) == 1)
        }

        private func mockEnvironment() throws {
            let environment = try #require(Environment.mocked)
            environment.variables["TUIST_TOKEN"] = "project-token"
            environment.variables["TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS"] = "0"
        }

        private func coverageFile() async throws -> AbsolutePath {
            let file = try #require(FileSystem.temporaryTestDirectory).appending(component: "coverage.json")
            try await FileSystem().writeText("coverage", at: file)
            return file
        }

        private func createAttachment(uploadURL: URL) async throws -> String {
            let file = try #require(FileSystem.temporaryTestDirectory).appending(component: "attachment.txt")
            try await FileSystem().writeText("attachment", at: file)
            let server = AttachmentServer(uploadURL: uploadURL)
            return try await Client.$additionalMiddlewares.withValue([server]) {
                try await CreateTestCaseRunAttachmentService(urlSession: ScriptedStorage.session).createAttachment(
                    fullHandle: "acme/app",
                    serverURL: URL(string: "https://test.tuist.dev")!,
                    testCaseRunId: "test-case-run-id",
                    fileName: "attachment.txt",
                    filePath: file,
                    repetitionNumber: nil,
                    testCaseRunArgumentId: nil
                )
            }
        }
    }

    enum StorageStep: Sendable, CustomTestStringConvertible {
        case status(Int, body: Data = Data())
        case dropConnection

        var testDescription: String {
            switch self {
            case let .status(code, _): "HTTP \(code)"
            case .dropConnection: "connection dropped"
            }
        }
    }

    /// Storage that answers each URL it scripted with the next of its steps, and records the bodies it received.
    final class ScriptedStorage: URLProtocol {
        private static let scripts = Mutex<[String: [StorageStep]]>([:])
        private static let receivedBodies = Mutex<[String: [Data]]>([:])

        static let session: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ScriptedStorage.self]
            return URLSession(configuration: configuration)
        }()

        static func script(_ steps: [StorageStep]) -> URL {
            let url = URL(string: "https://storage.test/\(UUID().uuidString)")!
            scripts.withLock { $0[url.path] = steps }
            return url
        }

        static func attempts(_ url: URL) -> Int {
            bodies(url).count
        }

        static func bodies(_ url: URL) -> [Data] {
            receivedBodies.withLock { $0[url.path] ?? [] }
        }

        override class func canInit(with _: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let path = request.url!.path
            let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
            Self.receivedBodies.withLock { $0[path, default: []].append(body) }
            let step = Self.scripts.withLock { scripts in
                scripts[path]?.isEmpty == false ? scripts[path]!.removeFirst() : .status(200)
            }
            switch step {
            case .dropConnection:
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            case let .status(code, body):
                let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() {}

        private static func read(_ stream: InputStream) -> Data {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            return data
        }
    }

    private struct AttachmentServer: ClientMiddleware {
        let uploadURL: URL

        func intercept(
            _: HTTPRequest,
            body _: HTTPBody?,
            baseURL _: URL,
            operationID: String,
            next _: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
        ) async throws -> (HTTPResponse, HTTPBody?) {
            #expect(operationID == "createTestCaseRunAttachment")
            var response = HTTPResponse(status: .created)
            response.headerFields[.contentType] = "application/json"
            return (
                response,
                HTTPBody(#"{"id":"attachment-id","upload_url":"\#(uploadURL.absoluteString)","expires_at":0}"#)
            )
        }
    }
#endif
