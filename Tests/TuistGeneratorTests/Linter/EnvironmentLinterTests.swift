import Foundation
import TuistSupport
import XCTest

@testable import TuistGenerator
@testable import TuistSupportTesting

final class EnvironmentLinterTests: TuistUnitTestCase {
    var subject: EnvironmentLinter!

    override func setUp() {
        super.setUp()
        subject = EnvironmentLinter()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_lintXcodeVersion_returnsALintingIssue_when_theVersionsOfXcodeAreIncompatible() throws {
        // Given
        let config = TuistConfig.test(compatibleXcodeVersions: .list(["3.2.1"]))
        xcodeController.selectedStub = .success(Xcode.test(infoPlist: .test(version: "4.3.2")))

        // When
        let got = try subject.lintXcodeVersion(config: config)

        // Then
        let expectedMessage = "The project, which only supports the versions of Xcode 3.2.1, is not compatible with your selected version of Xcode, 4.3.2"
        XCTAssertTrue(got.contains(LintingIssue(reason: expectedMessage, severity: .error)))
    }

    func test_lintXcodeVersion_doesntReturnIssues_whenAllVersionsAreSupported() throws {
        // Given
        let config = TuistConfig.test(compatibleXcodeVersions: .all)
        xcodeController.selectedStub = .success(Xcode.test(infoPlist: .test(version: "4.3.2")))

        // When
        let got = try subject.lintXcodeVersion(config: config)

        // Then
        XCTEmpty(got)
    }

    func test_lintXcodeVersion_doesntReturnIssues_whenThereIsNoSelectedXcode() throws {
        // Given
        let config = TuistConfig.test(compatibleXcodeVersions: .list(["3.2.1"]))

        // When
        let got = try subject.lintXcodeVersion(config: config)

        // Then
        XCTEmpty(got)
    }

    func test_lintXcodeVersion_throws_when_theSelectedXcodeCantBeObtained() throws {
        // Given
        let config = TuistConfig.test(compatibleXcodeVersions: .list(["3.2.1"]))
        let error = NSError.test()
        xcodeController.selectedStub = .failure(error)

        // Then
        XCTAssertThrowsError(try subject.lintXcodeVersion(config: config)) {
            XCTAssertEqual($0 as NSError, error)
        }
    }
}
