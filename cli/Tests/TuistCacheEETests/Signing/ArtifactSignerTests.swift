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
