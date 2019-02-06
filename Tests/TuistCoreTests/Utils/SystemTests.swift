import XCTest
@testable import TuistCore
@testable import TuistCoreTesting

final class SystemTests: XCTestCase {
    func test_run_valid_command() {
        let subject = System()
        
        XCTAssertNoThrow(try subject.run(["ls"]))
    }
    
    func test_run_invalid_command() {
        let subject = System()
        
        XCTAssertThrowsError(try subject.run(["abcdef", "ghi"]))
    }
    
    func test_run_valid_command_that_returns_nonzero_exit() {
        let subject = System()
        
        XCTAssertThrowsError(try subject.run(["ls", "abcdefghi"]))
    }
}
