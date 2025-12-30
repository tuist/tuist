import Foundation
import Path
import TuistSupport
import XCTest

@testable import TuistCacheEE
@testable import TuistTesting

final class PayloadEncryptorTests: TuistUnitTestCase {
    struct TestPayload: Codable, Equatable {
        let name: String
    }

    var subject: PayloadEncryptor!

    override func setUp() {
        super.setUp()
        subject = PayloadEncryptor()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_encrypt_and_decrypt_work() throws {
        // Given
        let payload = TestPayload(name: "test")
        let encrypted = try subject.encrypt(TestPayload(name: "test"), signableAttribute: \.name)
        let decrypted: TestPayload? = try subject.decrypt(encrypted, signableAttribute: \.name)

        // Then
        XCTAssertEqual(decrypted, payload)
    }

    func test_decrypt_returnsNil_when_theValueIsInvalid() throws {
        // When
        let decrypted: TestPayload? = try subject.decrypt("invalid", signableAttribute: \.name)

        // Then
        XCTAssertNil(decrypted)
    }

    func test_decrypt_returnsNil_when_theSignatureIsInvalid() throws {
        // Given
        var encrypted = try subject.encrypt(TestPayload(name: "test"), signableAttribute: \.name)
        encrypted = "\(encrypted.split(separator: ".")[0]).invalid"

        // When
        let decrypted: TestPayload? = try subject.decrypt(encrypted, signableAttribute: \.name)

        // Then
        XCTAssertNil(decrypted)
    }
}
