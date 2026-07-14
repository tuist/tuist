import Foundation
import Testing

@testable import TuistCacheEE

struct CacheSigningGrantVerifierTests {
    /// A throwaway Ed25519 keypair (private seed = bytes 0...31) generated only
    /// for these tests. It is NOT any real environment's key, so the tokens
    /// below are not usable credentials against staging or production — they
    /// only verify against `testPublicKey`, which the production binary never
    /// trusts.
    private let testPublicKey = "A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg="

    /// scope=account-test, iss=tuist-runners, aud=tuist-runner-cache,
    /// iat=1_700_000_000, exp=iat+3600 (1h — within the 24h lifetime cap).
    private let validToken =
        "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJ0dWlzdC1ydW5uZXJzIiwiYXVkIjoidHVpc3QtcnVubmVyLWNhY2hlIiwic2NvcGUiOiJhY2NvdW50LXRlc3QiLCJpYXQiOjE3MDAwMDAwMDAsImV4cCI6MTcwMDAwMzYwMH0.KCTlarX8GpvdnCB4g-NIi1x0Kt82H22WdygVYk41m1fzoxEEeWvXh0MbCQOouLej4JaHY0cYBK3ty5XUvgshCA"

    /// Same key/claims but exp=iat+10 years — a validly signed but effectively
    /// non-expiring grant, which the lifetime cap must reject.
    private let overlongToken =
        "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJ0dWlzdC1ydW5uZXJzIiwiYXVkIjoidHVpc3QtcnVubmVyLWNhY2hlIiwic2NvcGUiOiJhY2NvdW50LXRlc3QiLCJpYXQiOjE3MDAwMDAwMDAsImV4cCI6MjAxNTM2MDAwMH0.bjOA9MPpiSYQ0Pjznow-vHue5b9dtGlxuHRljZ0y87tvwac53_aW5_CMfTACz2d9EvYbUPiKXenywDFwACmtCw"

    private let beforeExpiry = Date(timeIntervalSince1970: 1_700_000_060)
    private let afterExpiry = Date(timeIntervalSince1970: 1_700_007_200)

    private var subject: CacheSigningGrantVerifier {
        CacheSigningGrantVerifier(publicKeyBase64: testPublicKey)
    }

    @Test func returns_the_scope_for_a_valid_unexpired_grant() {
        #expect(subject.verifiedScope(token: validToken, now: beforeExpiry) == "account-test")
    }

    @Test func returns_nil_when_expired() {
        #expect(subject.verifiedScope(token: validToken, now: afterExpiry) == nil)
    }

    @Test func returns_nil_when_the_lifetime_exceeds_the_cap() {
        // Authentic signature and claims, but exp - iat is far beyond the 24h
        // ceiling — the blast-radius bound on a leaked signing key.
        #expect(subject.verifiedScope(token: overlongToken, now: beforeExpiry) == nil)
    }

    @Test func returns_nil_for_a_tampered_payload() {
        // Flip the first character of the payload segment; the signature over
        // header.payload no longer matches.
        var parts = validToken.components(separatedBy: ".")
        let payload = parts[1]
        parts[1] = (payload.hasPrefix("e") ? "f" : "e") + payload.dropFirst()
        #expect(subject.verifiedScope(token: parts.joined(separator: "."), now: beforeExpiry) == nil)
    }

    @Test func returns_nil_when_verified_against_a_different_key() {
        // The same token, verified against the production baked key, must fail —
        // proof that verification is bound to the key, not just the claims.
        let production = CacheSigningGrantVerifier()
        #expect(production.verifiedScope(token: validToken, now: beforeExpiry) == nil)
    }

    @Test func returns_nil_for_malformed_tokens() {
        for bad in ["", "not-a-jwt", "only.two", "a.b.c.d"] {
            #expect(subject.verifiedScope(token: bad, now: beforeExpiry) == nil)
        }
    }
}
