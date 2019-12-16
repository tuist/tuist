import XCTest
import Basic
import TuistSupport

class SystemTests: XCTestCase {
    
    let sut = System.shared
    
    func test_pass_DEVELOPER_DIR() throws {
        
        try sandbox("DEVELOPER_DIR", value: "/Applications/Xcode/Xcode-10.2.1.app/Contents/Developer/") {
            let result = try sut.capture("env")
            XCTAssertTrue(result.contains("DEVELOPER_DIR"))
        }

    }
    
    func test_without_DEVELOPER_DIR() throws {
        let result = try sut.capture("env")
        XCTAssertFalse(result.contains("DEVELOPER_DIR"))
    }
    
    func test_do_not_pass_SECRET_VARIABLE() throws {
        
        try sandbox("SECRET_VARIABLE", value: "password") {
            let result = try sut.capture("env")
            XCTAssertFalse(result.contains("SECRET_VARIABLE"))
        }

    }
    
    func sandbox(_ name: String, value: String, do block: () throws -> Void) rethrows {
        try? ProcessEnv.setVar(name, value: value)
        _ = try? block()
        try? ProcessEnv.unsetVar(name)
    }

}
