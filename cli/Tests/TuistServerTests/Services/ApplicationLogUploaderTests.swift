#if !os(Linux)
    import Foundation
    import Mockable
    import Testing
    import TuistLogging
    import TuistTesting

    @testable import TuistServer

    struct ApplicationLogUploaderTests {
        private let serverURL = URL(string: "https://tuist.dev")!
        private let uploadAppLogsService = MockUploadAppLogsServicing()

        @Test(.withMockedDependencies()) func uploads_and_removes_queued_batches() async throws {
            let queue = ApplicationLogUploadQueueStub(batches: [batch(id: "first"), batch(id: "second")])
            givenSignedIn()
            given(uploadAppLogsService).uploadAppLogs(.any, serverURL: .value(serverURL)).willReturn()

            await subject(queue: queue).upload()

            #expect(await queue.sealCount == 1)
            #expect(await queue.batches.isEmpty)
            verify(uploadAppLogsService).uploadAppLogs(.any, serverURL: .any).called(2)
        }

        @Test(.withMockedDependencies()) func keeps_the_queue_while_signed_out() async throws {
            let queue = ApplicationLogUploadQueueStub(batches: [batch(id: "first")])
            let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
            given(serverCredentialsStore).read(serverURL: .any).willReturn(nil)

            await subject(queue: queue).upload()

            #expect(await queue.batches.map(\.id) == ["first"])
            verify(uploadAppLogsService).uploadAppLogs(.any, serverURL: .any).called(0)
        }

        @Test(.withMockedDependencies()) func keeps_the_batch_when_the_upload_fails() async throws {
            let queue = ApplicationLogUploadQueueStub(batches: [batch(id: "first"), batch(id: "second")])
            givenSignedIn()
            given(uploadAppLogsService).uploadAppLogs(.any, serverURL: .any)
                .willThrow(UploadAppLogsServiceError.unavailable(503))

            await subject(queue: queue).upload()

            #expect(await queue.batches.map(\.id) == ["first", "second"])
            verify(uploadAppLogsService).uploadAppLogs(.any, serverURL: .any).called(1)
        }

        @Test(.withMockedDependencies()) func drops_a_batch_the_server_rejects() async throws {
            let queue = ApplicationLogUploadQueueStub(batches: [batch(id: "first"), batch(id: "second")])
            givenSignedIn()
            given(uploadAppLogsService).uploadAppLogs(.any, serverURL: .any)
                .willThrow(UploadAppLogsServiceError.rejected(400))

            await subject(queue: queue).upload()

            #expect(await queue.batches.isEmpty)
        }

        private func subject(queue: ApplicationLogUploadQueueStub) -> ApplicationLogUploader {
            ApplicationLogUploader(serverURL: serverURL, queue: queue, uploadAppLogsService: uploadAppLogsService)
        }

        private func givenSignedIn() {
            given(ServerCredentialsStore.mocked!)
                .read(serverURL: .any)
                .willReturn(ServerCredentials(accessToken: "access", refreshToken: "refresh"))
        }

        private func batch(id: String) -> ApplicationLogBatch {
            ApplicationLogBatch(
                id: id,
                entries: [
                    ApplicationLogEntry(
                        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                        level: .notice,
                        source: "TuistAuthentication",
                        message: "Authentication state updated to logged out",
                        launchID: "launch"
                    ),
                ]
            )
        }
    }

    private actor ApplicationLogUploadQueueStub: ApplicationLogUploadQueuing {
        private(set) var batches: [ApplicationLogBatch]
        private(set) var sealCount = 0

        init(batches: [ApplicationLogBatch]) {
            self.batches = batches
        }

        nonisolated func append(_: ApplicationLogEntry) {}

        func seal() async {
            sealCount += 1
        }

        func nextBatch() async -> ApplicationLogBatch? {
            batches.first
        }

        func remove(_ batch: ApplicationLogBatch) async {
            batches.removeAll { $0.id == batch.id }
        }
    }
#endif
