import Foundation
@testable import ProjectDescription
import XCTest

final class HeadersTests: XCTestCase {
    func test_toJSON() {
        let subject = Headers(public: "public", private: "private", project: "project")

        XCTAssertEqual(subject.toJSON().toString(), "{\"private\": \"private\", \"project\": \"project\", \"public\": \"public\"}")
    }
}
