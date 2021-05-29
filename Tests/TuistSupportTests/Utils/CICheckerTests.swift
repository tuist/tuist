import Foundation
import XCTest
@testable import TuistSupport

final class CICheckerTests: XCTestCase {
    var subject: CIChecker!

    override func setUp() {
        super.setUp()
        subject = CIChecker()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func testIsCI_when_isCI() {
        // Given
        let env = ["CI": "1"]

        // When
        let got = subject.isCI(environment: env)

        // Then
        XCTAssertTrue(got)
    }

    func testIsCI_when_isNotCI() {
        // Given
        let env: [String: String] = [:]

        // When
        let got = subject.isCI(environment: env)

        // Then
        XCTAssertFalse(got)
    }
}
