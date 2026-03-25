import FileSystem
import FileSystemTesting
import Testing
import TuistSupport
import TuistTesting
@testable import TuistKit

@Suite(.withMockedDependencies()) struct PluginRunServiceTests {
    private let system = MockSystem()
    private var subject: PluginRunService!

    init() {
        subject = PluginRunService()
    }

    @Test(.inTemporaryDirectory) func run_with_arguments() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)

        system.succeedCommand([
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
        try subject.run(
            path: path.pathString,
            configuration: .release,
            buildTests: true,
            skipBuild: true,
            task: "my-task",
            arguments: ["my-argument-1", "my-argument-2"]
        )
    }

    @Test func run_with_no_arguments() throws {
        // Given
        system.succeedCommand([
            "swift", "run",
            "--configuration", PluginCommand.PackageConfiguration.debug.rawValue,
            "my-task",
        ])

        // When / Then
        try subject.run(
            path: nil,
            configuration: .debug,
            buildTests: false,
            skipBuild: false,
            task: "my-task",
            arguments: []
        )
    }
}
