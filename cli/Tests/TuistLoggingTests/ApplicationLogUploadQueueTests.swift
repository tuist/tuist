#if !os(Linux)
    import FileSystem
    import FileSystemTesting
    import Foundation
    import Path
    import Testing

    @testable import TuistLogging

    struct ApplicationLogUploadQueueTests {
        @Test(.inTemporaryDirectory)
        func batches_contain_appended_entries_until_removed() async throws {
            let subject = ApplicationLogUploadQueue(directory: try temporaryDirectory())
            let entry = entry(message: "Authentication state updated to logged out")

            subject.append(entry)
            await subject.seal()
            let batch = try #require(await subject.nextBatch())

            #expect(batch.entries == [entry])
            #expect(await subject.nextBatch() == batch)

            await subject.remove(batch)

            #expect(await subject.nextBatch() == nil)
        }

        @Test(.inTemporaryDirectory)
        func entries_from_a_previous_launch_are_uploaded() async throws {
            let directory = try temporaryDirectory()
            let entry = entry(message: "Signing out")
            let previousLaunch = ApplicationLogUploadQueue(directory: directory)
            previousLaunch.append(entry)
            await previousLaunch.seal()

            let subject = ApplicationLogUploadQueue(directory: directory)

            #expect(await subject.nextBatch()?.entries == [entry])
        }

        @Test(.inTemporaryDirectory)
        func entries_logged_after_a_batch_is_taken_go_into_the_next_batch() async throws {
            let subject = ApplicationLogUploadQueue(directory: try temporaryDirectory())
            let first = entry(message: "first")
            let second = entry(message: "second")

            subject.append(first)
            await subject.seal()
            let firstBatch = try #require(await subject.nextBatch())
            subject.append(second)
            await subject.remove(firstBatch)
            await subject.seal()

            #expect(await subject.nextBatch()?.entries == [second])
        }

        @Test(.inTemporaryDirectory)
        func long_messages_are_truncated() async throws {
            let subject = ApplicationLogUploadQueue(directory: try temporaryDirectory())

            subject.append(entry(message: String(repeating: "a", count: ApplicationLogUploadQueue.maximumMessageLength + 1)))
            await subject.seal()

            let message = try #require(await subject.nextBatch()?.entries.first?.message)
            #expect(message.count == ApplicationLogUploadQueue.maximumMessageLength)
        }

        @Test(.inTemporaryDirectory)
        func only_the_newest_batches_are_kept() async throws {
            let subject = ApplicationLogUploadQueue(directory: try temporaryDirectory())

            for index in 0 ..< 7 {
                subject.append(entry(message: "batch \(index)"))
                await subject.seal()
            }

            var messages: [String] = []
            while let batch = await subject.nextBatch() {
                messages.append(contentsOf: batch.entries.map(\.message))
                await subject.remove(batch)
            }
            #expect(messages == ["batch 2", "batch 3", "batch 4", "batch 5", "batch 6"])
        }

        @Test(.inTemporaryDirectory)
        func expired_batches_are_dropped() async throws {
            let directory = try temporaryDirectory()
            let subject = ApplicationLogUploadQueue(directory: directory)
            subject.append(entry(message: "stale"))
            await subject.seal()
            let batch = try #require(await subject.nextBatch())
            try await FileSystem().setFileTimes(
                of: try AbsolutePath(validating: directory.appendingPathComponent(batch.id).path),
                lastAccessDate: nil,
                lastModificationDate: Date().addingTimeInterval(-3 * 24 * 60 * 60 - 1)
            )

            await subject.seal()
            #expect(await subject.nextBatch() == nil)
        }

        @Test(.inTemporaryDirectory)
        func log_handler_queues_redacted_messages() async throws {
            let queue = ApplicationLogUploadQueue(directory: try temporaryDirectory())
            let handler = ApplicationLogUploadLogHandler(
                launchID: "launch",
                queue: queue,
                lineTransformer: ApplicationLogStore.redacted
            )
            let logger = Logger(label: "dev.tuist.app", factory: { _ in handler })

            logger.notice("Signed in as someone@example.com", metadata: ["refresh_token": "credential"])
            await queue.seal()

            let entry = try #require(await queue.nextBatch()?.entries.first)
            #expect(entry.level == .notice)
            #expect(entry.launchID == "launch")
            #expect(!entry.message.contains("someone@example.com"))
            #expect(!entry.message.contains("credential"))
        }

        private func entry(message: String) -> ApplicationLogEntry {
            ApplicationLogEntry(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                level: .notice,
                source: "TuistAuthentication",
                message: message,
                launchID: "launch"
            )
        }

        private func temporaryDirectory() throws -> URL {
            URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        }
    }
#endif
