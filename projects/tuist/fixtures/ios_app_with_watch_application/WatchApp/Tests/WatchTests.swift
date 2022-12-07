import XCTest
@testable import WatchApp

class WatchTests: XCTestCase {
    func dummyTest() async throws {
        XCTAssertEqual(WatchConfig.title, "Hello, watchOS")
    }
}
