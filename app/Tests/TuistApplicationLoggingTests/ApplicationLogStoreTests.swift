import FileSystem
import FileSystemTesting
import Foundation
import Testing

@testable import TuistLogging

struct ApplicationLogStoreTests {
    @Test(.inTemporaryDirectory)
    @MainActor
    func plain_text_report_contains_recent_persistent_logs() async throws {
        let logsDirectory = try temporaryLogsDirectory()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let subject = ApplicationLogStore(logsDirectory: logsDirectory)
        var handler = try subject.makeFileLogHandler(generatedAt: date)
        handler.logLevel = .debug
        let logger = Logger(label: "dev.tuist.app", factory: { _ in handler })

        logger.notice(
            "authentication refresh succeeded",
            metadata: ["attempt": "1"]
        )
        _ = try handler.contents()

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
    func sensitive_values_are_redacted_before_they_are_stored() throws {
        let logsDirectory = try temporaryLogsDirectory()
        let subject = ApplicationLogStore(logsDirectory: logsDirectory)
        var handler = try subject.makeFileLogHandler()
        handler.logLevel = .debug
        let logger = Logger(label: "dev.tuist.app", factory: { _ in handler })

        logger.error(
            "authorization=secret bearer another-secret",
            metadata: ["refresh_token": "credential", "request": "safe"]
        )
        let contents = try handler.contents()

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
    func verbose_http_bodies_are_not_stored() throws {
        let logsDirectory = try temporaryLogsDirectory()
        let subject = ApplicationLogStore(logsDirectory: logsDirectory)
        var handler = try subject.makeFileLogHandler()
        handler.logLevel = .debug
        let logger = Logger(label: "dev.tuist.app", factory: { _ in handler })
        let presignedURL = "https://storage.example.com/build?X-Amz-Credential=credential&X-Amz-Signature=signature"

        logger.debug("Received HTTP response from Tuist:\n  - Body: \(presignedURL)")

        #expect(try handler.contents().isEmpty)
    }

    @Test(.inTemporaryDirectory)
    @MainActor
    func only_the_two_most_recent_launches_are_retained() throws {
        let logsDirectory = try temporaryLogsDirectory()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let oldSessionURL = try makeSessionFile(
            named: "session-old.txt",
            contents: "old",
            modificationDate: date,
            in: logsDirectory
        )
        let recentSessionURL = try makeSessionFile(
            named: "session-recent.txt",
            contents: "recent",
            modificationDate: date.addingTimeInterval(1),
            in: logsDirectory
        )
        let subject = ApplicationLogStore(logsDirectory: logsDirectory)

        _ = try subject.makeFileLogHandler(generatedAt: date.addingTimeInterval(2))

        let retainedFiles = try FileManager.default.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(retainedFiles.count == 2)
        #expect(!FileManager.default.fileExists(atPath: oldSessionURL.path))
        #expect(FileManager.default.fileExists(atPath: recentSessionURL.path))
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
        defer {
            for exportedURL in exportedURLs {
                try? FileManager.default.removeItem(at: exportedURL)
            }
        }

        #expect(Set(exportedURLs).count == 2)
    }

    private func temporaryLogsDirectory() throws -> URL {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        return URL(fileURLWithPath: temporaryDirectory.pathString, isDirectory: true)
    }

    private func makeSessionFile(
        named name: String,
        contents: String,
        modificationDate: Date,
        in directory: URL
    ) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate],
            ofItemAtPath: fileURL.path
        )
        return fileURL
    }
}

private struct ApplicationLogStoreStub: ApplicationLogStoring {
    let exportURL: URL

    @MainActor func bootstrap() {}

    func plainTextExport() async throws -> URL {
        exportURL
    }
}
