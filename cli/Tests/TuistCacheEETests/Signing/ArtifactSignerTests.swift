import Path
import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistCacheEE

final class ArtifactSignerTests: TuistTestCase {
    var subject: ArtifactSigner!

    override func setUp() {
        super.setUp()
        subject = ArtifactSigner()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_crud() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        let filePath = temporaryDirectory.appending(component: "Test")
        try "Test".write(to: filePath.url, atomically: true, encoding: .utf8)

        // When
        XCTAssertFalse(try subject.isValid(filePath))
        try subject.sign(filePath)
        XCTAssertTrue(try subject.isValid(filePath))
        try subject.removeSignature(filePath)
        XCTAssertFalse(try subject.isValid(filePath))
    }
}

struct ArtifactSigningCacheTests {
    @Test func reusesEncryptionWhileResolvingScopeForEverySignature() throws {
        let payload = MockArtifactSignaturePayloadProvider()
        let encryptor = MockPayloadEncryptor()
        let attributes = MockExtendedAttributesController()
        payload.stubbedFetchResult = .success(.init(macAddress: "account-scope"))
        encryptor.stubbedEncryptResult = .success("account-signature")
        let signer = ArtifactSigner(
            payloadEncryptor: encryptor,
            signatureCache: ArtifactSigningCache(),
            extendedAttributesController: attributes,
            artifactSignaturePayloadProvider: payload
        )
        let path = try AbsolutePath(validating: "/unused")
        try signer.sign(path)
        try signer.sign(path)
        #expect(encryptor.invokedEncryptCount == 1)
        #expect(payload.invokedFetchCount == 2)
        #expect(attributes.invokedSetAttributeParametersList.map(\.value) == ["account-signature", "account-signature"])

        payload.stubbedFetchResult = .success(.init(macAddress: "machine-after-grant-expiry"))
        encryptor.stubbedEncryptResult = .success("machine-signature")
        try signer.sign(path)
        #expect(encryptor.invokedEncryptCount == 2)
        #expect(payload.invokedFetchCount == 3)
        #expect(attributes.invokedSetAttributeParameters?.value == "machine-signature")
    }
}
