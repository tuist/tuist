import TSCBasic
import TuistSigningTesting
import XCTest
@testable import TuistKit
@testable import TuistSupportTesting

final class DecryptServiceTests: TuistUnitTestCase {
    var subject: DecryptService!
    var signingCipher: MockSigningCipher!

    override func setUp() {
        super.setUp()

        signingCipher = MockSigningCipher()
        subject = DecryptService(signingCipher: signingCipher)
    }

    override func tearDown() {
        signingCipher = nil
        subject = nil
        super.tearDown()
    }

    func test_calls_decrypt_with_provided_path() throws {
        // Given
        let expectedPath = try AbsolutePath(validating: "/path")
        var path: AbsolutePath?
        signingCipher.decryptSigningStub = { decryptPath, _ in
            path = decryptPath
        }

        // When
        try subject.run(path: expectedPath.pathString)

        // Then
        XCTAssertEqual(path, expectedPath)
    }
}
