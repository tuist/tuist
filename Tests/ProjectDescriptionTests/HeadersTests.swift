import Foundation
import TuistCoreTesting
import XCTest

@testable import ProjectDescription

final class HeadersTests: XCTestCase {
    func test_toJSON() {
        let subject = Headers(public: "public", private: "private", project: "project")

        XCTAssertCodableEqualToJson(subject, "{\"public\":{\"globs\":[\"public\"]},\"private\":{\"globs\":[\"private\"]},\"project\":{\"globs\":[\"project\"]}}")
    }
}
