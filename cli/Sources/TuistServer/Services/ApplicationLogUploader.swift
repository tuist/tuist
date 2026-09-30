#if !os(Linux)
    import Foundation
    import TuistLogging

    /// Uploads the app's queued log lines to the Tuist server while the user is signed in.
    ///
    /// Lines logged while signed out stay queued and upload after the next sign-in. A batch the server rejects as
    /// invalid is dropped so it cannot block the queue; any other failure keeps the batch for the next run.
    public actor ApplicationLogUploader {
        private static let maximumBatchesPerRun = 10

        private let serverURL: URL
        private let queue: any ApplicationLogUploadQueuing
        private let uploadAppLogsService: any UploadAppLogsServicing
        private var isUploading = false

        public init(
            serverURL: URL,
            queue: any ApplicationLogUploadQueuing = ApplicationLogUploadQueue.current,
            uploadAppLogsService: any UploadAppLogsServicing = UploadAppLogsService()
        ) {
            self.serverURL = serverURL
            self.queue = queue
            self.uploadAppLogsService = uploadAppLogsService
        }

        public func run(initialDelay: Duration = .seconds(30), interval: Duration = .seconds(300)) async {
            try? await Task.sleep(for: initialDelay)
            while !Task.isCancelled {
                await upload()
                try? await Task.sleep(for: interval)
            }
        }

        public func upload() async {
            guard !isUploading else { return }
            isUploading = true
            defer { isUploading = false }

            guard (try? await ServerCredentialsStore.current.read(serverURL: serverURL)) != nil else { return }

            await queue.seal()
            for _ in 0 ..< Self.maximumBatchesPerRun {
                guard let batch = await queue.nextBatch() else { return }
                do {
                    try await uploadAppLogsService.uploadAppLogs(batch.entries, serverURL: serverURL)
                    await queue.remove(batch)
                } catch UploadAppLogsServiceError.rejected {
                    await queue.remove(batch)
                } catch {
                    return
                }
            }
        }
    }
#endif
