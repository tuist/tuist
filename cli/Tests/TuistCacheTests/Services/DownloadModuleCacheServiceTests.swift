import CryptoKit
import Foundation
import Testing

@testable import TuistCache

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
}
