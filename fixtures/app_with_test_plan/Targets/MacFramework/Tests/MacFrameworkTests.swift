import Foundation
import XCTest

@testable import MacFramework

final class MacFrameworkTests: XCTestCase {
    func testHello() {
        let sut = MacFramework()

        XCTAssertEqual("MacFramework.hello()", sut.hello())
    }
    
    func testWorld() {
        let sut = MacFramework()
        
        XCTAssertEqual("MacFramework.world()", sut.world())
    }
}
