import CryptoKit
import Foundation
import Testing

@testable import TuistCache

struct CacheCASServiceChecksumTests {
    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test func a_save_declares_the_digest_of_the_bytes_it_sends() {
        let data = Data("compressed cas object".utf8)

        #expect(SaveCacheCASService.checksumSHA256(of: data) == sha256(data))
    }

    /// Objects uploaded without a digest, or served by a server that predates
    /// digests, arrive without one and are used exactly as before.
    @Test func a_load_without_a_digest_is_not_compared() {
        let data = Data("compressed cas object".utf8)

        #expect(LoadCacheCASService.checksumMismatch(of: data, declared: nil) == nil)
        #expect(LoadCacheCASService.checksumMismatch(of: data, declared: "") == nil)
    }

    @Test func a_load_that_matches_its_digest_passes_in_either_case() {
        let data = Data("compressed cas object".utf8)
        let digest = sha256(data)

        #expect(LoadCacheCASService.checksumMismatch(of: data, declared: digest) == nil)
        #expect(LoadCacheCASService.checksumMismatch(of: data, declared: digest.uppercased()) == nil)
    }

    @Test func a_load_that_does_not_match_its_digest_reports_both() throws {
        let data = Data("damaged in transit".utf8)
        let declared = String(repeating: "0", count: 64)

        let mismatch = try #require(LoadCacheCASService.checksumMismatch(of: data, declared: declared))

        guard case let .checksumMismatch(expected, actual) = mismatch else {
            Issue.record("Expected a checksum mismatch, got \(mismatch)")
            return
        }
        #expect(expected == declared)
        #expect(actual == sha256(data))
    }
}
