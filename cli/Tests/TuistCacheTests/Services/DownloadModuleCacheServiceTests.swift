import CryptoKit
import Foundation
import Mockable
import Testing
import TuistEnvironment
import TuistEnvironmentTesting
import TuistHTTP
import TuistServer

@testable import TuistCache

@Suite(.serialized)
struct DownloadModuleCacheServiceTests {
    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Artifacts uploaded before digests existed, or by a client that declared none,
    /// arrive without one and are used exactly as before.
    @Test func a_response_without_a_digest_is_not_compared() {
        let data = Data("artifact".utf8)

        #expect(DownloadModuleCacheService.checksumMismatch(of: data, declared: nil) == nil)
        #expect(DownloadModuleCacheService.checksumMismatch(of: data, declared: "") == nil)
    }

    @Test func a_body_that_matches_its_digest_passes_in_either_case() {
        let data = Data("artifact".utf8)
        let digest = sha256(data)

        #expect(DownloadModuleCacheService.checksumMismatch(of: data, declared: digest) == nil)
        #expect(DownloadModuleCacheService.checksumMismatch(of: data, declared: digest.uppercased()) == nil)
    }

    @Test func a_body_that_does_not_match_its_digest_reports_both() {
        let data = Data("damaged in transit".utf8)
        let declared = String(repeating: "0", count: 64)

        #expect(
            DownloadModuleCacheService.checksumMismatch(of: data, declared: declared) ==
                .checksumMismatch(expected: declared, actual: sha256(data))
        )
    }

    /// The error must not read as retryable: the service has already fetched the
    /// artifact a second time, and a copy damaged at rest does not repair.
    @Test func a_checksum_mismatch_is_not_retryable() {
        let error = DownloadModuleCacheServiceError.checksumMismatch(
            expected: String(repeating: "0", count: 64),
            actual: String(repeating: "1", count: 64)
        )

        #expect(error.isRetryable == false)
    }

    @Test func a_download_cut_off_partway_resumes_and_is_verified_as_a_whole() async throws {
        let server = try await LocalArtifactServer(replies: [
            .init(status: 200, headers: headers(for: artifact), body: artifact.prefix(100_000)),
            .init(status: 206, headers: headers(for: artifact, from: 100_000), body: artifact.dropFirst(100_000)),
        ])

        let data = try await download(from: server)

        #expect(data == artifact)
        #expect(server.requests == [.init(range: nil, ifRange: nil), .init(range: "bytes=100000-", ifRange: etag)])
    }

    @Test func a_download_that_stalls_resumes_once_the_inactivity_timeout_fires() async throws {
        let server = try await LocalArtifactServer(replies: [
            .init(status: 200, headers: headers(for: artifact), body: artifact.prefix(100_000), stallsAfterBody: true),
            .init(status: 206, headers: headers(for: artifact, from: 100_000), body: artifact.dropFirst(100_000)),
        ])

        let data = try await download(from: server, inactivityTimeout: 1)

        #expect(data == artifact)
        #expect(server.requests == [.init(range: nil, ifRange: nil), .init(range: "bytes=100000-", ifRange: etag)])
    }

    /// The digest describes the whole artifact, so a tail damaged in flight fails the check like
    /// any other damage and the artifact is fetched again from the start.
    @Test func a_resumed_download_with_a_damaged_tail_is_fetched_again() async throws {
        var damagedTail = Data(artifact.dropFirst(100_000))
        damagedTail[0] ^= 0xFF
        let server = try await LocalArtifactServer(replies: [
            .init(status: 200, headers: headers(for: artifact), body: artifact.prefix(100_000)),
            .init(status: 206, headers: headers(for: artifact, from: 100_000), body: damagedTail),
            .init(status: 200, headers: headers(for: artifact), body: artifact),
        ])

        let data = try await download(from: server)

        #expect(data == artifact)
        #expect(server.requests.map(\.range) == [nil, "bytes=100000-", nil])
    }

    /// Each resumed tail is smaller than the bodies verbose logging buffers, so it has to reach resume
    /// as a stream for the bytes before each drop to be kept.
    @Test func a_small_tail_that_keeps_dropping_resumes_from_each_drop() async throws {
        let server = try await LocalArtifactServer(replies: [
            .init(status: 200, headers: headers(for: artifact), body: artifact.prefix(200_000)),
            .init(status: 206, headers: headers(for: artifact, from: 200_000), body: artifact.subdata(in: 200_000 ..< 220_000)),
            .init(status: 206, headers: headers(for: artifact, from: 220_000), body: artifact.subdata(in: 220_000 ..< 240_000)),
            .init(status: 206, headers: headers(for: artifact, from: 240_000), body: artifact.dropFirst(240_000)),
        ])

        let data = try await download(from: server)

        #expect(data == artifact)
        #expect(server.requests.map(\.range) == [nil, "bytes=200000-", "bytes=220000-", "bytes=240000-"])
    }

    @Test func a_discarded_retryable_response_stops_its_transfer() async throws {
        let server = try await LocalArtifactServer(replies: [
            .init(
                status: 503,
                headers: ["Content-Type": "application/json", "Content-Length": "100000"],
                body: Data(repeating: 0x20, count: 1000),
                stallsAfterBody: true
            ),
            .init(status: 200, headers: headers(for: artifact), body: artifact),
        ])
        let session = session()
        defer { session.invalidateAndCancel() }

        let data = try await download(from: server, session: session, admission: TransferAdmission(limit: 4))
        var closedStalls = server.closedStalls
        for _ in 0 ..< 50 where closedStalls == 0 {
            try await Task.sleep(for: .milliseconds(100))
            closedStalls = server.closedStalls
        }

        #expect(data == artifact)
        #expect(closedStalls == 1)
    }

    /// Each transfer below keeps making progress for longer than the inactivity timeout, over a
    /// single connection. A download handed to the session while another holds that connection
    /// would time out in its queue before sending a request.
    @Test(.withMockedEnvironment())
    func downloads_waiting_for_a_connection_do_not_time_out() async throws {
        try #require(Environment.mocked).variables["TUIST_HTTP_MAXIMUM_RETRY_COUNT"] = "0"
        let trickle = LocalArtifactServer.Reply(
            status: 200,
            headers: headers(for: artifact),
            body: artifact,
            chunkSize: 16384,
            chunkDelayMilliseconds: 100
        )
        let server = try await LocalArtifactServer(replies: [trickle, trickle, trickle])
        let session = session(inactivityTimeout: 1, maximumConnectionsPerHost: 1)
        defer { session.invalidateAndCancel() }
        let admission = TransferAdmission(limit: session.configuration.httpMaximumConnectionsPerHost)

        let downloads = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0 ..< 3 {
                group.addTask { try await download(from: server, session: session, admission: admission) }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(downloads == [artifact, artifact, artifact])
    }

    /// Larger than the bodies verbose logging buffers, so it reaches resume as a stream.
    private let artifact = Data((0 ..< 262_144).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    private let etag = "\"1-262144\""

    private func headers(for artifact: Data, from offset: Int = 0) -> [String: String] {
        var headers = [
            "Content-Type": "application/octet-stream",
            "Content-Length": String(artifact.count - offset),
            "ETag": etag,
            "tuist-checksum-sha256": sha256(artifact),
        ]
        if offset > 0 {
            headers["Content-Range"] = "bytes \(offset)-\(artifact.count - 1)/\(artifact.count)"
        }
        return headers
    }

    private func session(inactivityTimeout: TimeInterval = 60, maximumConnectionsPerHost: Int = 4) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = inactivityTimeout
        configuration.httpMaximumConnectionsPerHost = maximumConnectionsPerHost
        return URLSession(configuration: configuration)
    }

    private func download(from server: LocalArtifactServer, inactivityTimeout: TimeInterval = 60) async throws -> Data {
        let session = session(inactivityTimeout: inactivityTimeout)
        defer { session.invalidateAndCancel() }
        return try await download(from: server, session: session, admission: TransferAdmission(limit: 4))
    }

    private func download(
        from server: LocalArtifactServer,
        session: URLSession,
        admission: TransferAdmission
    ) async throws -> Data {
        let authenticationController = MockServerAuthenticationControlling()
        given(authenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        return try await DownloadModuleCacheService(session: { session }, admission: admission)
            .downloadModuleCacheArtifact(
                accountHandle: "account",
                projectHandle: "project",
                hash: "hash",
                name: "Module.xcframework.zip",
                cacheCategory: "builds",
                serverURL: server.url,
                authenticationURL: URL(string: "http://127.0.0.1:1")!,
                serverAuthenticationController: authenticationController
            )
    }
}
