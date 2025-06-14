import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class ProductTests: XCTestCase {
    func test_toJSON() {
        XCTAssertCodableEqualToJson([Product.app], "[\"app\"]")
        XCTAssertCodableEqualToJson([Product.staticLibrary], "[\"static_library\"]")
        XCTAssertCodableEqualToJson([Product.dynamicLibrary], "[\"dynamic_library\"]")
        XCTAssertCodableEqualToJson([Product.framework], "[\"framework\"]")
        XCTAssertCodableEqualToJson([Product.unitTests], "[\"unit_tests\"]")
        XCTAssertCodableEqualToJson([Product.uiTests], "[\"ui_tests\"]")
        XCTAssertCodableEqualToJson([Product.appClip], "[\"appClip\"]")
    }
}
