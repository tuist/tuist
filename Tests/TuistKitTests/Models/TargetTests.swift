import Foundation
@testable import TuistKit
import XCTest

final class TargetTests: XCTestCase {
    func test_validSourceExtensions() {
        XCTAssertEqual(Target.validSourceExtensions, ["m", "swift", "mm", "cpp", "c"])
    }
    
    func test_productName_when_staticLibrary() {
        let target = Target.test(name: "Test", product: .staticLibrary)
        XCTAssertEqual(target.productName, "libTest.a")
    }
    
    func test_productName_when_dynamicLibrary() {
        let target = Target.test(name: "Test", product: .dynamicLibrary)
        XCTAssertEqual(target.productName, "libTest.dylib")
    }
    
    func test_productName_when_app() {
        let target = Target.test(name: "Test", product: .app)
        XCTAssertEqual(target.productName, "Test.app")
    }
}
