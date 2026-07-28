import Foundation
import Testing
import TuistEnvironment
import TuistEnvironmentTesting

@testable import TuistCacheEE
@testable import TuistTesting

struct ArtifactSignaturePayloadProviderTests {
    @Test func fetch_returnsAPayloadWithNonEmptyMacAddress() async throws {
        try await withMockedEnvironment {
            // No grant in the environment: falls back to the machine MAC.
            let got = try ArtifactSignaturePayloadProvider().fetch()
            #expect(got.macAddress != "")
        }
    }

    @Test func fetch_usesTheGrantScope_whenAValidGrantIsPresent() async throws {
        try await withMockedEnvironment {
            // A runner environment with a grant that verifies to an account
            // scope: the signable payload becomes the account scope, not the
            // MAC, so a warm volume's artifacts validate across the account's VMs.
            let verifier = MockCacheSigningGrantVerifier()
            verifier.stubbedVerifiedScopeResult = "account-123"
            Environment.mocked?.variables["TUIST_CACHE_SIGNING_GRANT"] = "signed-grant-token"
            let subject = ArtifactSignaturePayloadProvider(
                macAddressProvider: MacAddressProvider(),
                grantVerifier: verifier
            )

            let got = try subject.fetch()

            #expect(got.macAddress == "account-123")
            #expect(verifier.invokedVerifiedScopeToken == "signed-grant-token")
        }
    }

    @Test func fetch_fallsBackToMac_whenTheGrantDoesNotVerify() async throws {
        try await withMockedEnvironment {
            // An invalid/expired grant: verification returns nil and the provider
            // falls back to the machine MAC, exactly like a dev machine.
            let verifier = MockCacheSigningGrantVerifier()
            verifier.stubbedVerifiedScopeResult = nil
            Environment.mocked?.variables["TUIST_CACHE_SIGNING_GRANT"] = "bad-grant-token"
            let subject = ArtifactSignaturePayloadProvider(
                macAddressProvider: MacAddressProvider(),
                grantVerifier: verifier
            )

            let got = try subject.fetch()

            #expect(got.macAddress != "")
            #expect(!got.macAddress.hasPrefix("account-"))
        }
    }

    @Test func fetch_fallsBackToMac_whenNoGrantIsPresent() async throws {
        try await withMockedEnvironment {
            // No grant in the environment: the verifier is never consulted.
            let verifier = MockCacheSigningGrantVerifier()
            verifier.stubbedVerifiedScopeResult = "account-999"
            let subject = ArtifactSignaturePayloadProvider(
                macAddressProvider: MacAddressProvider(),
                grantVerifier: verifier
            )

            let got = try subject.fetch()

            #expect(!verifier.invokedVerifiedScope)
            #expect(got.macAddress != "")
            #expect(!got.macAddress.hasPrefix("account-"))
        }
    }
}
