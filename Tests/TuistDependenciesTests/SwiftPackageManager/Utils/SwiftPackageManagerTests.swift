import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class SwiftPackageManagerTests: TuistUnitTestCase {
    private var subject: SwiftPackageManager!
    
    override func setUp() {
        super.setUp()

        subject = SwiftPackageManager()
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }
    
    func test_resolve() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "resolve"
        ])
        
        // When
        XCTAssertNoThrow(try subject.resolve(at: path))
    }
}
