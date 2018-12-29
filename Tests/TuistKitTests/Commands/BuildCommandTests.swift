import Foundation
import XCTest

@testable import TuistKit

final class BuildCommandTests: XCTestCase {
    func test_command() {
        XCTAssertEqual(BuildCommand.command, "build")
    }

    func test_overview() {
        XCTAssertEqual(BuildCommand.overview, "Builds a project target.")
    }
}
