import Foundation
import XCTest

@testable import Core

final class CoreTests: XCTestCase {
    
    func testHello() {
        let sut = CoreFile()
        
        XCTAssertEqual("CoreTests.hello()", sut.hello())
    }
    
}
