import Foundation
import Path
import Testing
import TuistEnvironment
import TuistEnvironmentTesting
@testable import TuistKit

struct CASProxyFailureServiceTests {
    private let subject = CASProxyFailureService()

    @Test(.withMockedEnvironment())
    func returnsTheLatestFailureRecordedDuringTheBuild() async throws {
        let buildStartedAt = Date()
        try writeRecord(
            named: "build-100-1111",
            error: "proxy connect: Connection refused (os error 61)",
            failedAt: buildStartedAt.addingTimeInterval(1)
        )
        try writeRecord(
            named: "service-100",
            error: "proxy recv: Resource temporarily unavailable (os error 35)",
            failedAt: buildStartedAt.addingTimeInterval(2)
        )

        let failure = try await subject.failure(since: buildStartedAt)

        #expect(
            failure == CASProxyFailure(
                socket: "/tmp/cas-proxy.sock",
                error: "proxy recv: Resource temporarily unavailable (os error 35)"
            )
        )
    }

    @Test(.withMockedEnvironment())
    func ignoresFailuresRecordedBeforeTheBuildStarted() async throws {
        let buildStartedAt = Date()
        try writeRecord(
            named: "build-100-1111",
            error: "proxy connect: Connection refused (os error 61)",
            failedAt: buildStartedAt.addingTimeInterval(-60)
        )

        let failure = try await subject.failure(since: buildStartedAt)

        #expect(failure == nil)
    }

    @Test(.withMockedEnvironment())
    func skipsARecordItCannotRead() async throws {
        let buildStartedAt = Date()
        let directory = try recordDirectory()
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        try Data("not a record".utf8).write(to: directory.appending(component: "build-100-2222.json").url)
        try writeRecord(
            named: "build-100-1111",
            error: "proxy connect: Connection refused (os error 61)",
            failedAt: buildStartedAt.addingTimeInterval(1)
        )

        let failure = try await subject.failure(since: buildStartedAt)

        #expect(failure?.error == "proxy connect: Connection refused (os error 61)")
    }

    @Test(.withMockedEnvironment())
    func returnsNothingWhenNoFailureWasRecorded() async throws {
        let failure = try await subject.failure(since: .distantPast)

        #expect(failure == nil)
    }

    private func recordDirectory() throws -> AbsolutePath {
        let environment = try #require(Environment.mocked)
        return environment.casProxySocketPath().parentDirectory
            .appending(component: "cas-proxy-failures")
    }

    /// The shape `cas-plugin/src/proxy_failure.rs` writes.
    private func writeRecord(named name: String, error: String, failedAt: Date) throws {
        let directory = try recordDirectory()
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        let failedAtMilliseconds = Int(failedAt.timeIntervalSince1970 * 1000)
        let record = #"{"socket":"/tmp/cas-proxy.sock","error":"\#(error)","failed_at_ms":\#(failedAtMilliseconds)}"#
        try Data(record.utf8).write(to: directory.appending(component: "\(name).json").url)
    }
}
