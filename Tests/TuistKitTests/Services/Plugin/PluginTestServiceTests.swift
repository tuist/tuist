import TSCBasic
import TuistSupport
import TuistSupportTesting
import XCTest
@testable import TuistKit

final class PluginTestServiceTests: TuistUnitTestCase {
    private var subject: PluginTestService!

    override func setUp() {
        super.setUp()
        subject = PluginTestService()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_run_with_arguments() throws {
        // Given
        let path = try temporaryPath()

        system.succeedCommand([
            "swift", "test",
            "--configuration", PluginCommand.PackageConfiguration.release.rawValue,
            "--package-path", path.pathString,
            "--build-tests",
            "--test-product", "MyProduct1",
            "--test-product", "MyProduct2",
        ])

        // When / Then
        XCTAssertNoThrow(
            try subject.run(
                path: path.pathString,
                configuration: .release,
                buildTests: true,
                testProducts: ["MyProduct1", "MyProduct2"]
            )
        )
    }

    func test_run_with_no_arguments() throws {
        // Given
        system.succeedCommand([
            "swift", "test",
            "--configuration", PluginCommand.PackageConfiguration.debug.rawValue,
        ])

        // When / Then
        XCTAssertNoThrow(
            try subject.run(
                path: nil,
                configuration: .debug,
                buildTests: false,
                testProducts: []
            )
        )
    }
}
