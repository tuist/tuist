import Foundation
import XCTest

@testable import StaticFramework

final class MyObjcppClassTests: XCTestCase {
    func testHello() {
        XCTAssertNotNil(MyObjcppClass())
    }
}
