import TuistSupport
import TuistTesting
import XCTest
@testable import TuistKit

final class PluginBuildServiceTests: TuistUnitTestCase {
    private var subject: PluginBuildService!

    override func setUp() {
        super.setUp()
        subject = PluginBuildService(commandRunner: mockCommandRunner)
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_run_with_arguments() async throws {
        // Given
        let path = try temporaryPath()

        mockCommandRunner.succeedCommand([
            "swift", "build",
            "--configuration", PluginCommand.PackageConfiguration.release.rawValue,
            "--package-path", path.pathString,
            "--build-tests",
            "--show-bin-path",
            "--target", "MyTarget1",
            "--target", "MyTarget2",
            "--product", "MyProduct1",
            "--product", "MyProduct2",
        ])

        // When
        try await subject.run(
            path: path.pathString,
            configuration: .release,
            buildTests: true,
            showBinPath: true,
            targets: ["MyTarget1", "MyTarget2"],
            products: ["MyProduct1", "MyProduct2"]
        )
    }

    func test_run_with_no_arguments() async throws {
        // Given
        mockCommandRunner.succeedCommand([
            "swift", "build",
            "--configuration", PluginCommand.PackageConfiguration.debug.rawValue,
        ])

        // When
        try await subject.run(
            path: nil,
            configuration: .debug,
            buildTests: false,
            showBinPath: false,
            targets: [],
            products: []
        )
    }
}
