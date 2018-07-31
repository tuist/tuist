import Foundation
@testable import TuistEnvKit
import Utility
import XCTest

final class UpdateCommandTests: XCTestCase {
    func test_command() {
        XCTAssertEqual(UpdateCommand.command, "update")
    }

    func test_overview() {
        XCTAssertEqual(UpdateCommand.overview, "Installs the latest version if it's not already installed")
    }
}
