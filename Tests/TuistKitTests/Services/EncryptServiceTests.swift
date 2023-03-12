import TSCBasic
import TuistSigningTesting
import XCTest
@testable import TuistKit
@testable import TuistSupportTesting

final class EncryptServiceTests: TuistUnitTestCase {
    var subject: EncryptService!
    var signingCipher: MockSigningCipher!

    override func setUp() {
        super.setUp()

        signingCipher = MockSigningCipher()
        subject = EncryptService(signingCipher: signingCipher)
    }

    override func tearDown() {
        signingCipher = nil
        subject = nil
        super.tearDown()
    }

    func test_calls_encrypt_with_provided_path() throws {
        // Given
        let expectedPath = try AbsolutePath(validating: "/path")
        var path: AbsolutePath?
        signingCipher.encryptSigningStub = { encryptPath, _ in
            path = encryptPath
        }

        // When
        try subject.run(path: expectedPath.pathString)

        // Then
        XCTAssertEqual(path, expectedPath)
    }
}
