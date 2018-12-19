import Foundation
@testable import TuistKit
import XCTest

final class TargetTests: XCTestCase {
    func test_validSourceExtensions() {
        XCTAssertEqual(Target.validSourceExtensions, ["m", "swift", "mm", "cpp", "c"])
    }
}
