import TuistSupport
import TuistTesting
import XCTest
@testable import TuistKit

final class PluginRunServiceTests: TuistUnitTestCase {
    private var subject: PluginRunService!

    override func setUp() {
        super.setUp()
        subject = PluginRunService(commandRunner: mockCommandRunner)
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_run_with_arguments() async throws {
        // Given
        let path = try temporaryPath()

        mockCommandRunner.succeedCommand([
            "swift", "run",
            "--configuration", PluginCommand.PackageConfiguration.release.rawValue,
            "--package-path", path.pathString,
            "--build-tests",
            "--skip-build",
            "my-task",
            "my-argument-1",
            "my-argument-2",
        ])

        // When / Then
        try await subject.run(
            path: path.pathString,
            configuration: .release,
            buildTests: true,
            skipBuild: true,
            task: "my-task",
            arguments: ["my-argument-1", "my-argument-2"]
        )
    }

    func test_run_with_no_arguments() async throws {
        // Given
        mockCommandRunner.succeedCommand([
            "swift", "run",
            "--configuration", PluginCommand.PackageConfiguration.debug.rawValue,
            "my-task",
        ])

        // When / Then
        try await subject.run(
            path: nil,
            configuration: .debug,
            buildTests: false,
            skipBuild: false,
            task: "my-task",
            arguments: []
        )
    }
}
