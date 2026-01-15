import StaticResourcesFramework
import XCTest

final class ResourceBundleTests: XCTestCase {
    func test_readsResourceFromStaticFrameworkBundle() throws {
        let message = try ResourceReader().message()
        XCTAssertEqual(message, "Hello from StaticResourcesFramework")
    }
}
