import Foundation
import Path
import Testing
import TuistSupport

@testable import TuistCacheEE
@testable import TuistTesting

struct PayloadEncryptorTests {
    struct TestPayload: Codable, Equatable {
        let name: String
    }

    let subject: PayloadEncryptor
    init() {
        subject = PayloadEncryptor()
    }

    @Test
    func encrypt_and_decrypt_work() throws {
        // Given
        let payload = TestPayload(name: "test")
        let encrypted = try subject.encrypt(TestPayload(name: "test"), signableAttribute: \.name)
        let decrypted: TestPayload? = try subject.decrypt(encrypted, signableAttribute: \.name)

        // Then
        #expect(decrypted == payload)
    }

    @Test
    func decrypt_returnsNil_when_theValueIsInvalid() throws {
        // When
        let decrypted: TestPayload? = try subject.decrypt("invalid", signableAttribute: \.name)

        // Then
        #expect(decrypted == nil)
    }

    @Test
    func decrypt_returnsNil_when_theSignatureIsInvalid() throws {
        // Given
        var encrypted = try subject.encrypt(TestPayload(name: "test"), signableAttribute: \.name)
        encrypted = "\(encrypted.split(separator: ".")[0]).invalid"

        // When
        let decrypted: TestPayload? = try subject.decrypt(encrypted, signableAttribute: \.name)

        // Then
        #expect(decrypted == nil)
    }
}
