import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class HeadersTests: XCTestCase {
    func test_toJSON() {
        let subject = Headers(public: "public", private: "private", project: "project")
        XCTAssertCodable(subject)
    }
}
