import FileSystem
import FileSystemTesting
import Testing
import TuistSupport
import TuistTesting
@testable import TuistKit

struct PluginBuildServiceTests {
    private let system = MockSystem()
    private var subject: PluginBuildService!

    init() {
        subject = PluginBuildService()
    }

    @Test(.inTemporaryDirectory) func run_with_arguments() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)

        system.succeedCommand([
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

        // When / Then
        try subject.run(
            path: path.pathString,
            configuration: .release,
            buildTests: true,
            showBinPath: true,
            targets: ["MyTarget1", "MyTarget2"],
            products: ["MyProduct1", "MyProduct2"]
        )
    }

    @Test func run_with_no_arguments() throws {
        // Given
        system.succeedCommand([
            "swift", "build",
            "--configuration", PluginCommand.PackageConfiguration.debug.rawValue,
        ])

        // When / Then
        try subject.run(
            path: nil,
            configuration: .debug,
            buildTests: false,
            showBinPath: false,
            targets: [],
            products: []
        )
    }
}
