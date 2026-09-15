import Foundation
import Path
import Testing
import TuistEnvironment
import TuistEnvironmentTesting
@testable import TuistKit

struct CASProxyFailureServiceTests {
    private let subject = CASProxyFailureService()

    @Test(.withMockedEnvironment())
    func returnsTheFailureRecordedDuringTheBuild() async throws {
        let buildStartedAt = Date().addingTimeInterval(-60)
        let error = "proxy connect: Connection refused (os error 61)"
        try writeRecord(socket: "/tmp/cas-proxy.sock", error: error)

        let failure = try await subject.failure(since: buildStartedAt)

        #expect(failure == CASProxyFailure(socket: "/tmp/cas-proxy.sock", error: error))
    }

    @Test(.withMockedEnvironment())
    func ignoresAFailureRecordedBeforeTheBuildStarted() async throws {
        try writeRecord(socket: "/tmp/cas-proxy.sock", error: "proxy connect: Connection refused (os error 61)")

        let failure = try await subject.failure(since: Date().addingTimeInterval(60))

        #expect(failure == nil)
    }

    @Test(.withMockedEnvironment())
    func returnsNothingWhenNoFailureWasRecorded() async throws {
        let failure = try await subject.failure(since: .distantPast)

        #expect(failure == nil)
    }

    /// The shape `cas-plugin/src/proxy_failure.rs` writes beside the proxy socket.
    private func writeRecord(socket: String, error: String) throws {
        let environment = try #require(Environment.mocked)
        let recordPath = environment.casProxySocketPath().parentDirectory
            .appending(component: CASProxyFailureService.recordFileName)
        let record = #"{"socket":"\#(socket)","error":"\#(error)","builder_pid":4242}"#
        try Data(record.utf8).write(to: recordPath.url)
    }
}
