import Foundation
import TSCBasic
import TuistCore
import TuistLoader
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistSupportTesting

final class SecretServiceTests: TuistUnitTestCase {
    var subject: SecretService!
    var secureStringGenerator: MockSecureStringGenerator!

    override func setUp() {
        super.setUp()
        secureStringGenerator = MockSecureStringGenerator()
        subject = SecretService(secureStringGenerator: secureStringGenerator)
    }

    override func tearDown() {
        subject = nil
        secureStringGenerator = nil
        super.tearDown()
    }

    func test_run() throws {
        // Given
        secureStringGenerator.generateStub = .success("secret")

        // When
        try subject.run()

        // Then
        XCTAssertPrinterOutputContains("secret")
    }

    func test_run_errors_when_the_secure_string_cant_be_generated() throws {
        // Given
        let error = TestError("couldn't generate secure string")
        secureStringGenerator.generateStub = .failure(error)

        // Then
        XCTAssertThrowsSpecific(try subject.run(), error)
    }
}
