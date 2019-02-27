import Foundation
import XCTest
@testable import ProjectDescription

final class ProductTests: XCTestCase {
    func test_toJSON() {
        assertCodableEqualToJson([Product.app], "[\"app\"]")
        assertCodableEqualToJson([Product.staticLibrary], "[\"static_library\"]")
        assertCodableEqualToJson([Product.dynamicLibrary], "[\"dynamic_library\"]")
        assertCodableEqualToJson([Product.framework], "[\"framework\"]")
        assertCodableEqualToJson([Product.unitTests], "[\"unit_tests\"]")
        assertCodableEqualToJson([Product.uiTests], "[\"ui_tests\"]")
    }
}
