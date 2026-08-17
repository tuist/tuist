import Foundation
import Pulse
import Testing

@testable import TuistLogging

struct ApplicationLogStoreTests {
    @Test func plain_text_report_contains_recent_persistent_logs() async throws {
        let store = try makeStore()
        defer { try? store.destroy() }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let subject = ApplicationLogStore()

        store.storeMessage(
            createdAt: date,
            label: "dev.tuist.app",
            level: .notice,
            message: "authentication refresh succeeded",
            metadata: ["attempt": .string("1")],
            file: "AuthenticationService.swift",
            function: "refresh()",
            line: 42
        )

        let report = try await subject.plainTextReport(
            store: store,
            appVersion: "1.2.3",
            appBuild: "456",
            operatingSystemVersion: "test operating system",
            generatedAt: date.addingTimeInterval(1)
        )

        #expect(report.contains("Tuist application logs"))
        #expect(report.contains("App version: 1.2.3 (456)"))
        #expect(report.contains("notice | dev.tuist.app | authentication refresh succeeded"))
        #expect(report.contains("metadata=attempt=1"))
        #expect(report.contains("source=AuthenticationService.swift:42"))
    }

    @Test func sanitizer_redacts_authentication_values() throws {
        let subject = ApplicationLogStore()
        let event = LoggerStore.Event.messageStored(
            .init(
                createdAt: Date(),
                label: "dev.tuist.app",
                level: .error,
                message: "authorization=secret bearer another-secret",
                metadata: ["refresh_token": "credential", "request": "safe"],
                file: "Test.swift",
                function: "test()",
                line: 1
            )
        )

        let sanitizedEvent = subject.sanitized(event)
        let message = try #require(sanitizedEvent.message)

        #expect(message.message == "authorization=[redacted] bearer [redacted]")
        #expect(message.metadata?["refresh_token"] == "[redacted]")
        #expect(message.metadata?["request"] == "safe")
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

    @Test func concurrent_exports_use_distinct_files() async throws {
        let subject = ApplicationLogStore()
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

    private func makeStore() throws -> LoggerStore {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return try LoggerStore(
            storeURL: storeURL,
            options: [.create, .sweep, .synchronous],
            configuration: .init(sizeLimit: 1_000_000)
        )
    }
}

private struct ApplicationLogStoreStub: ApplicationLogStoring {
    let exportURL: URL

    @MainActor func bootstrap() {}

    func plainTextExport() async throws -> URL {
        exportURL
    }
}

extension LoggerStore.Event {
    fileprivate var message: LoggerStore.Event.MessageCreated? {
        guard case let .messageStored(message) = self else { return nil }
        return message
    }
}
