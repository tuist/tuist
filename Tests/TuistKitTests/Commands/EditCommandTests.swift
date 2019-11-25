import Basic
import Foundation
import SPMUtility
import XcodeProj
import XCTest
@testable import TuistKit
@testable import TuistSupportTesting

final class EditCommandTests: TuistUnitTestCase {
    func test_command() {
        XCTAssertEqual(EditCommand.command, "edit")
    }

    func test_overview() {
        XCTAssertEqual(EditCommand.overview, "Generates a temporary project to edit the project in the current directory")
    }
}
