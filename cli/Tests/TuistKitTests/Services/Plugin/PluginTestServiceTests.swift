import FileSystem
import FileSystemTesting
import Testing
import TuistSupport
import TuistTesting
@testable import TuistKit

struct PluginTestServiceTests {
    private let system = MockSystem()
    private var subject: PluginTestService!

    init() {
        subject = PluginTestService()
    }

    @Test(.inTemporaryDirectory) func run_with_arguments() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)

        system.succeedCommand([
            "swift", "test",
            "--configuration", PluginCommand.PackageConfiguration.release.rawValue,
            "--package-path", path.pathString,
            "--build-tests",
            "--test-product", "MyProduct1",
            "--test-product", "MyProduct2",
        ])

        // When / Then
        try subject.run(
            path: path.pathString,
            configuration: .release,
            buildTests: true,
            testProducts: ["MyProduct1", "MyProduct2"]
        )
    }

    @Test func run_with_no_arguments() throws {
        // Given
        system.succeedCommand([
            "swift", "test",
            "--configuration", PluginCommand.PackageConfiguration.debug.rawValue,
        ])

        // When / Then
        try subject.run(
            path: nil,
            configuration: .debug,
            buildTests: false,
            testProducts: []
        )
    }
}
