import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class GalaxyTests: XCTestCase {
    func test_codable() throws {
        let subject = Galaxy(token: "token")
        XCTAssertCodable(subject)
    }
}
