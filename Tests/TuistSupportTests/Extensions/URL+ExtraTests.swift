import Foundation
import XCTest
import TuistSupport

// I (danibachar) have added these tests to show the fact that this validation might not be the best approach
// One might want to migrate to Regex validation

final class URLExtraConsumerTests: XCTestCase {
    func test_valid_url() {
        XCTAssertTrue(URL.isValid("https://google.com"))
        XCTAssertTrue(URL.isValid("https:/google.com"))
        XCTAssertTrue(URL.isValid("https:/google"))
        XCTAssertTrue(URL.isValid("https:google.com"))
        XCTAssertTrue(URL.isValid("ws://google.com"))
        XCTAssertTrue(URL.isValid("wss://google.com:443"))
        XCTAssertTrue(URL.isValid("google.com"))
        XCTAssertTrue(URL.isValid("google"))
        XCTAssertTrue(URL.isValid("1"))
    }
    
    func test_non_valid_url_empty() {
        XCTAssertFalse(URL.isValid(""))
    }
}
