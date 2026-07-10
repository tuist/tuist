import Foundation
import TuistTesting
import XCTest

@testable import TuistCacheEE

final class CacheSigningGrantVerifierTests: TuistUnitTestCase {
    var subject: CacheSigningGrantVerifier!

    /// A real EdDSA grant signed by the staging cache-grant private key whose
    /// public half is baked into CacheSigningGrantVerifier. Claims:
    /// scope=account-123, aud=tuist-runner-cache, iss=tuist-runners,
    /// iat=1_700_000_000, exp=4_102_444_800 (year 2100).
    private let validToken =
        "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJ0dWlzdC1ydW5uZXItY2FjaGUiLCJleHAiOjQxMDI0NDQ4MDAsImlhdCI6MTcwMDAwMDAwMCwiaXNzIjoidHVpc3QtcnVubmVycyIsInNjb3BlIjoiYWNjb3VudC0xMjMifQ.Ek6wJsTj10gzs17d3I_-Z8NGKZpZHiuwySgI7O5sH6rQ1rFgu4MKn4cCbYE5SAJbTR8OCimaCpqCLmZJOnfuAA"

    /// A time well before the fixture's exp.
    private let beforeExpiry = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        subject = CacheSigningGrantVerifier()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_verifiedScope_returnsScope_forAValidUnexpiredGrant() {
        XCTAssertEqual(subject.verifiedScope(token: validToken, now: beforeExpiry), "account-123")
    }

    func test_verifiedScope_returnsNil_whenExpired() {
        // now is past the fixture's exp (year 2100).
        let afterExpiry = Date(timeIntervalSince1970: 5_000_000_000)
        XCTAssertNil(subject.verifiedScope(token: validToken, now: afterExpiry))
    }

    func test_verifiedScope_returnsNil_forATamperedPayload() {
        // Flip a character in the payload segment; the signature no longer
        // matches the signed message.
        var parts = validToken.components(separatedBy: ".")
        let payload = parts[1]
        let tampered = payload.hasPrefix("e") ? "f" + payload.dropFirst() : "e" + payload.dropFirst()
        parts[1] = String(tampered)
        let tamperedToken = parts.joined(separator: ".")

        XCTAssertNil(subject.verifiedScope(token: tamperedToken, now: beforeExpiry))
    }

    func test_verifiedScope_returnsNil_forMalformedTokens() {
        XCTAssertNil(subject.verifiedScope(token: "", now: beforeExpiry))
        XCTAssertNil(subject.verifiedScope(token: "not-a-jwt", now: beforeExpiry))
        XCTAssertNil(subject.verifiedScope(token: "only.two", now: beforeExpiry))
        XCTAssertNil(subject.verifiedScope(token: "a.b.c.d", now: beforeExpiry))
    }
}
