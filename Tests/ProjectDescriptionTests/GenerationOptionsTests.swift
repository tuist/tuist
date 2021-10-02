import Foundation
import ProjectDescription
import XCTest

final class GenerationOptionsTests: XCTestCase {
    func test_enableCodeCoverage_backwardCompatibility() {
        XCTAssertEqual(Config.GenerationOptions.enableCodeCoverage, .enableCodeCoverage(.all))
    }
}
