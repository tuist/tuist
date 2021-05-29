import XCTest
@testable import ProjectDescription

final class PluginTests: XCTestCase {
    func test_codable() throws {
        let subject = Plugin(name: "TestPlugin")
        XCTAssertCodable(subject)
    }
}
