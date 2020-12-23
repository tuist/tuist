import TuistCore
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class CarthageCommandGeneratorTests: TuistUnitTestCase {
    private var subject: CarthageCommandGenerator!

    override func setUp() {
        super.setUp()
        subject = CarthageCommandGenerator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_command() throws {
        // Given
        let stubbedPath = try temporaryPath()
        let expected = "carthage bootstrap --project-directory \(stubbedPath.pathString) --use-netrc --cache-builds --new-resolver"

        // When
        let got = subject
            .command(path: stubbedPath, platforms: nil)
            .joined(separator: " ")

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_command_with_platforms() throws {
        // Given
        let stubbedPath = try temporaryPath()
        let expected = "carthage bootstrap --project-directory \(stubbedPath.pathString) --platform iOS --use-netrc --cache-builds --new-resolver"

        // When
        let got = subject
            .command(path: stubbedPath, platforms: [.iOS])
            .joined(separator: " ")

        // Then
        XCTAssertEqual(got, expected)
    }
}
