import TuistCore
import TuistEnvironment
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistCacheEE

final class ArtifactSignaturePayloadProviderTests: TuistUnitTestCase {
    var subject: ArtifactSignaturePayloadProvider!

    override func setUp() {
        super.setUp()
        subject = ArtifactSignaturePayloadProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_fetch_returnsAPayloadWithNonEmptyMacAddress() throws {
        // Given/When
        let got = try subject.fetch()

        // Then
        XCTAssertNotEqual(got.macAddress, "")
    }

    func test_fetch_usesTheGrantScope_whenAValidGrantIsPresent() throws {
        // Given a runner environment with a grant that verifies to an account
        // scope: the signable payload becomes the account scope, not the MAC,
        // so a warm volume's artifacts validate across VMs of the account.
        let verifier = MockCacheSigningGrantVerifier()
        verifier.stubbedVerifiedScopeResult = "account-123"
        Environment.mocked?.variables["TUIST_CACHE_SIGNING_GRANT"] = "signed-grant-token"
        subject = ArtifactSignaturePayloadProvider(
            macAddressProvider: MacAddressProvider(),
            grantVerifier: verifier
        )

        // When
        let got = try subject.fetch()

        // Then
        XCTAssertEqual(got.macAddress, "account-123")
        XCTAssertEqual(verifier.invokedVerifiedScopeToken, "signed-grant-token")
    }

    func test_fetch_fallsBackToMac_whenTheGrantDoesNotVerify() throws {
        // Given an invalid/expired grant: verification returns nil and the
        // provider falls back to the machine MAC, exactly like a dev machine.
        let verifier = MockCacheSigningGrantVerifier()
        verifier.stubbedVerifiedScopeResult = nil
        Environment.mocked?.variables["TUIST_CACHE_SIGNING_GRANT"] = "bad-grant-token"
        subject = ArtifactSignaturePayloadProvider(
            macAddressProvider: MacAddressProvider(),
            grantVerifier: verifier
        )

        // When
        let got = try subject.fetch()

        // Then
        XCTAssertNotEqual(got.macAddress, "")
        XCTAssertFalse(got.macAddress.hasPrefix("account-"))
    }

    func test_fetch_fallsBackToMac_whenNoGrantIsPresent() throws {
        // Given no grant in the environment: the verifier is never consulted.
        let verifier = MockCacheSigningGrantVerifier()
        verifier.stubbedVerifiedScopeResult = "account-999"
        Environment.mocked?.variables["TUIST_CACHE_SIGNING_GRANT"] = nil
        subject = ArtifactSignaturePayloadProvider(
            macAddressProvider: MacAddressProvider(),
            grantVerifier: verifier
        )

        // When
        let got = try subject.fetch()

        // Then
        XCTAssertFalse(verifier.invokedVerifiedScope)
        XCTAssertNotEqual(got.macAddress, "")
        XCTAssertFalse(got.macAddress.hasPrefix("account-"))
    }
}
