import Foundation
import Testing

@testable import TuistServer

struct ApplicationLogStoreTests {
    @Test func report_contains_environment_and_logs_without_credential_values() async {
        let store = ApplicationLogStore(maximumEntryCount: 10)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        await store.record(
            level: .notice,
            category: "authentication",
            message: "token_refresh_started access_token_expires_at=known",
            at: date
        ).value
        await store.record(
            level: .error,
            category: "previews",
            message: "request_failed error_type=PreviewError",
            at: date.addingTimeInterval(1)
        ).value

        let report = await store.report(
            appVersion: "1.2.3",
            appBuild: "456",
            operatingSystemVersion: "test operating system",
            generatedAt: date.addingTimeInterval(2)
        )

        #expect(report.contains("Tuist application logs"))
        #expect(report.contains("App version: 1.2.3 (456)"))
        #expect(report.contains("Operating system: test operating system"))
        #expect(report.contains("notice | authentication | token_refresh_started"))
        #expect(report.contains("error | previews | request_failed error_type=PreviewError"))
        #expect(report.contains("Authentication credential values are not recorded"))
    }

    @Test func report_keeps_only_the_most_recent_entries() async {
        let store = ApplicationLogStore(maximumEntryCount: 2)

        await store.record(level: .info, category: "test", message: "first").value
        await store.record(level: .info, category: "test", message: "second").value
        await store.record(level: .info, category: "test", message: "third").value

        let report = await store.report(
            appVersion: "1",
            appBuild: "1",
            operatingSystemVersion: "test"
        )

        #expect(!report.contains("| first"))
        #expect(report.contains("| second"))
        #expect(report.contains("| third"))
    }

    @Test func recording_task_can_be_awaited_when_the_entry_must_be_available() async {
        let store = ApplicationLogStore()

        let recordingTask = store.record(
            level: .debug,
            category: "test",
            message: "fire-and-forget"
        )
        await recordingTask.value

        let report = await store.report(
            appVersion: "1",
            appBuild: "1",
            operatingSystemVersion: "test"
        )

        #expect(report.contains("debug | test | fire-and-forget"))
    }
}
