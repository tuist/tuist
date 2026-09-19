#if !os(Linux)
    import FileSystem
    import FileSystemTesting
    import Foundation
    import Path
    import Testing

    @testable import TuistLogging

    struct ApplicationLogStoreTests {
        @Test(.inTemporaryDirectory)
        @MainActor
        func plain_text_report_contains_recent_persistent_logs() async throws {
            let logsDirectory = try temporaryLogsDirectory()
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            let subject = ApplicationLogStore(logsDirectory: logsDirectory)
            var handler = try await subject.makeFileLogHandler(generatedAt: date)
            handler.logLevel = .debug
            let logger = Logger(label: "dev.tuist.app", factory: { _ in handler })

            logger.notice(
                "authentication refresh succeeded",
                metadata: ["attempt": "1"]
            )
            _ = try await handler.contents()

            let report = try await subject.plainTextReport(
                appVersion: "1.2.3",
                appBuild: "456",
                operatingSystemVersion: "test operating system",
                generatedAt: date.addingTimeInterval(1)
            )

            #expect(report.contains("Tuist application logs"))
            #expect(report.contains("App version: 1.2.3 (456)"))
            #expect(report.contains("[notice]"))
            #expect(report.contains("authentication refresh succeeded"))
            #expect(report.contains("attempt"))
        }

        @Test(.inTemporaryDirectory)
        @MainActor
        func sensitive_values_are_redacted_before_they_are_stored() async throws {
            let logsDirectory = try temporaryLogsDirectory()
            let subject = ApplicationLogStore(logsDirectory: logsDirectory)
            var handler = try await subject.makeFileLogHandler()
            handler.logLevel = .debug
            let logger = Logger(label: "dev.tuist.app", factory: { _ in handler })

            logger.error(
                "authorization=secret bearer another-secret",
                metadata: ["refresh_token": "credential", "request": "safe"]
            )
            let contents = try await handler.contents()

            #expect(!contents.contains("authorization=secret"))
            #expect(!contents.contains("another-secret"))
            #expect(!contents.contains("credential"))
            #expect(contents.contains("authorization=[redacted]"))
            #expect(contents.contains("bearer [redacted]"))
            #expect(contents.contains("refresh_token"))
            #expect(contents.contains("request"))
            #expect(contents.contains("safe"))
        }

        @Test(.inTemporaryDirectory)
        @MainActor
        func verbose_http_bodies_are_not_stored() async throws {
            let logsDirectory = try temporaryLogsDirectory()
            let subject = ApplicationLogStore(logsDirectory: logsDirectory)
            var handler = try await subject.makeFileLogHandler()
            handler.logLevel = .debug
            let logger = Logger(label: "dev.tuist.app", factory: { _ in handler })
            let presignedURL = "https://storage.example.com/build?X-Amz-Credential=credential&X-Amz-Signature=signature"

            logger.debug("Received HTTP response from Tuist:\n  - Body: \(presignedURL)")

            #expect(try await handler.contents().isEmpty)
        }

        @Test(.inTemporaryDirectory)
        @MainActor
        func only_the_two_most_recent_launches_are_retained() async throws {
            let logsDirectory = try temporaryLogsDirectory()
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            let fileSystem = FileSystem()
            let oldSessionPath = try await makeSessionFile(
                named: "session-old.txt",
                contents: "old",
                modificationDate: date,
                in: logsDirectory,
                fileSystem: fileSystem
            )
            let recentSessionPath = try await makeSessionFile(
                named: "session-recent.txt",
                contents: "recent",
                modificationDate: date.addingTimeInterval(1),
                in: logsDirectory,
                fileSystem: fileSystem
            )
            let subject = ApplicationLogStore(logsDirectory: logsDirectory, fileSystem: fileSystem)

            _ = try await subject.makeFileLogHandler(generatedAt: date.addingTimeInterval(2))

            let retainedFiles = try await fileSystem.contentsOfDirectory(logsDirectory)
            #expect(retainedFiles.count == 2)
            #expect(try await !fileSystem.exists(oldSessionPath))
            #expect(try await fileSystem.exists(recentSessionPath))
        }

        @Test(.inTemporaryDirectory)
        @MainActor
        func expired_launches_are_removed() async throws {
            let logsDirectory = try temporaryLogsDirectory()
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            let fileSystem = FileSystem()
            let expiredSessionPath = try await makeSessionFile(
                named: "session-expired.txt",
                contents: "expired",
                modificationDate: date.addingTimeInterval(-3 * 24 * 60 * 60 - 1),
                in: logsDirectory,
                fileSystem: fileSystem
            )
            let subject = ApplicationLogStore(logsDirectory: logsDirectory, fileSystem: fileSystem)

            _ = try await subject.makeFileLogHandler(generatedAt: date)

            #expect(try await !fileSystem.exists(expiredSessionPath))
        }

        @Test func current_can_be_overridden_for_a_task() async throws {
            let expectedURL = URL(fileURLWithPath: "/tmp/tuist-logs.txt")
            let override = ApplicationLogStoreStub(exportURL: expectedURL)

            let exportedURL = try await ApplicationLogStore.$current.withValue(override) {
                try await Task {
                    try await ApplicationLogStore.current.plainTextExport()
                }.value
            }

            #expect(exportedURL == expectedURL)
        }

        @Test(.inTemporaryDirectory)
        func concurrent_exports_use_distinct_files() async throws {
            let logsDirectory = try temporaryLogsDirectory()
            let subject = ApplicationLogStore(logsDirectory: logsDirectory)
            let exportedURLs = try await withThrowingTaskGroup(of: URL.self) { group in
                for _ in 0 ..< 2 {
                    group.addTask {
                        try await subject.plainTextExport()
                    }
                }

                return try await group.reduce(into: []) { $0.append($1) }
            }
            #expect(Set(exportedURLs).count == 2)
            for exportedURL in exportedURLs {
                try await FileSystem().remove(try AbsolutePath(validating: exportedURL.path))
            }
        }

        @Test(.inTemporaryDirectory)
        func plain_text_export_writes_the_report_to_a_unique_file() async throws {
            let logsDirectory = try temporaryLogsDirectory()
            let fileSystem = FileSystem()
            let subject = ApplicationLogStore(logsDirectory: logsDirectory, fileSystem: fileSystem)

            let exportURL = try await subject.plainTextExport()
            let exportPath = try AbsolutePath(validating: exportURL.path)

            #expect(try await fileSystem.exists(exportPath))
            #expect(try await fileSystem.readTextFile(at: exportPath).contains("Tuist application logs"))
            try await fileSystem.remove(exportPath)
        }

        private func temporaryLogsDirectory() throws -> AbsolutePath {
            try #require(FileSystem.temporaryTestDirectory)
        }

        private func makeSessionFile(
            named name: String,
            contents: String,
            modificationDate: Date,
            in directory: AbsolutePath,
            fileSystem: FileSysteming
        ) async throws -> AbsolutePath {
            let filePath = directory.appending(component: name)
            try await fileSystem.writeText(contents, at: filePath)
            try await fileSystem.setFileTimes(
                of: filePath,
                lastAccessDate: nil,
                lastModificationDate: modificationDate
            )
            return filePath
        }
    }

    private struct ApplicationLogStoreStub: ApplicationLogStoring {
        let exportURL: URL

        @MainActor func bootstrap() async {}

        func plainTextExport() async throws -> URL {
            exportURL
        }
    }
#endif
