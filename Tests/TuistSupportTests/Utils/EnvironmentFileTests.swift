import Foundation
import TSCBasic
import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

final class EnvironmentFileTests: TuistUnitTestCase {
    private var subject: TuistSupport.Environment!
    private let fileManager = FileManager.default
    
    override func setUp() {
        super.setUp()
        subject = Environment()
    }
    
    override func tearDown() {
        subject = nil
        super.tearDown()
    }
    
    // MARK: - Tests
    
    func test_loading_env_values_from_file() {
        let path = try temporaryPath()
        let file = path.appending(".env")
        """
        API_KEY=some-value
        BUILD_NUMBER=5
        IDENTIFIER="com.app.example"
        MAIL_TEMPLATE="The "Quoted" Title"
        DB_PASSPHRASE="1qaz?#@"' wsx$"
        """.write(to: file.asURL, atomically: true, encoding: .utf8)
        
        XCTAssertEqual(subject.tuistVariables["API_KEY"], "some-value")
        XCTAssertEqual(subject.tuistVariables["BUILD_NUMBER"], "5")
        XCTAssertEqual(subject.tuistVariables["IDENTIFIER"], "com.app.example")
        XCTAssertEqual(subject.tuistVariables["MAIL_TEMPLATE"], "The \"Quoted\" Title")
        XCTAssertEqual(subject.tuistVariables["DB_PASSPHRASE"], "1qaz?#@\"' wsx$")
    }
}
