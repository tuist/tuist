import Basic
import Foundation
import TuistCore
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

final class SettingsLinterTests: XCTestCase {
    var fileHandler: MockFileHandler!
    var subject: SettingsLinter!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
        subject = SettingsLinter(fileHandler: fileHandler)
    }

    func test_lint_when_config_files_are_missing() {
        let debugPath = fileHandler.currentPath.appending(component: "Debug.xcconfig")
        let releasePath = fileHandler.currentPath.appending(component: "Release.xcconfig")

        let settings = Settings(debug: Configuration(xcconfig: debugPath),
                                release: Configuration(xcconfig: releasePath))

        let got = subject.lint(settings: settings)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Configuration file not found at path \(debugPath.asString)", severity: .error)))
        XCTAssertTrue(got.contains(LintingIssue(reason: "Configuration file not found at path \(releasePath.asString)", severity: .error)))
    }
}
