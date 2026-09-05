import ExampleLibrary
import XCTest

final class ExampleLibraryTests: XCTestCase {
    func test_greeting() {
        XCTAssertEqual(Greeting.message, "Hello from ExampleLibrary")
    }
}
