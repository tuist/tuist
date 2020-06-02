import XCTest
import TSCBasic
import TuistSigningTesting
@testable import TuistSupportTesting
@testable import TuistKit

final class EncryptServiceTests: TuistUnitTestCase {
    var subject: EncryptService!
    var signingCipher: MockSigningCipher!
    
    override func setUp() {
        super.setUp()
        
        signingCipher = MockSigningCipher()
        subject = EncryptService(signingCipher: signingCipher)
    }
    
    override func tearDown() {
        super.tearDown()
        
        signingCipher = nil
        subject = nil
    }
    
    func test_calls_encrypt_with_provided_path() throws {
        // Given
        let expectedPath = AbsolutePath("/path")
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
