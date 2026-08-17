import Foundation
import Pulse
import Testing

@testable import TuistLogging

struct ApplicationLogStoreTests {
    @Test func plain_text_report_contains_recent_persistent_logs() async throws {
        let store = try makeStore()
        defer { try? store.destroy() }
        let date = Date(timeIntervalSince1970: 1_700_000_000)

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

        let report = try await ApplicationLogStore.plainTextReport(
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

        let sanitizedEvent = ApplicationLogStore.sanitized(event)
        let message = try #require(sanitizedEvent.message)

        #expect(message.message == "authorization=[redacted] bearer [redacted]")
        #expect(message.metadata?["refresh_token"] == "[redacted]")
        #expect(message.metadata?["request"] == "safe")
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

extension LoggerStore.Event {
    fileprivate var message: LoggerStore.Event.MessageCreated? {
        guard case let .messageStored(message) = self else { return nil }
        return message
    }
}
