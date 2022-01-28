import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistSupportTesting

final class SwiftPackageManagerControllerTests: TuistUnitTestCase {
    private var subject: SwiftPackageManagerController!

    override func setUp() {
        super.setUp()

        subject = SwiftPackageManagerController()
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
            "resolve",
        ])

        // When / Then
        XCTAssertNoThrow(try subject.resolve(at: path, printOutput: false))
    }

    func test_update() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "update",
        ])

        // When / Then
        XCTAssertNoThrow(try subject.update(at: path, printOutput: false))
    }

    func test_setToolsVersion_specificVersion() throws {
        // Given
        let path = try temporaryPath()
        let version = "5.4"
        system.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "tools-version",
            "--set",
            version,
        ])

        // When / Then
        XCTAssertNoThrow(try subject.setToolsVersion(at: path, to: version))
    }

    func test_setToolsVersion_currentVersion() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "tools-version",
            "--set-current",
        ])

        // When / Then
        XCTAssertNoThrow(try subject.setToolsVersion(at: path, to: nil))
    }

    func test_loadPackageInfo() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand(
            [
                "swift",
                "package",
                "--package-path",
                path.pathString,
                "dump-package",
            ],
            output: PackageInfo.testJSON
        )

        // When
        let packageInfo = try subject.loadPackageInfo(at: path)

        // Then
        XCTAssertEqual(packageInfo, PackageInfo.test)
    }

    func test_loadPackageInfo_alamofire() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand(
            [
                "swift",
                "package",
                "--package-path",
                path.pathString,
                "dump-package",
            ],
            output: PackageInfo.alamofireJSON
        )

        // When
        let packageInfo = try subject.loadPackageInfo(at: path)

        // Then
        XCTAssertEqual(packageInfo, PackageInfo.alamofire)
    }

    func test_loadPackageInfo_googleAppMeasurement() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand(
            [
                "swift",
                "package",
                "--package-path",
                path.pathString,
                "dump-package",
            ],
            output: PackageInfo.googleAppMeasurementJSON
        )

        // When
        let packageInfo = try subject.loadPackageInfo(at: path)

        // Then
        XCTAssertEqual(packageInfo, PackageInfo.googleAppMeasurement)
    }

    func test_buildFatReleaseBinary() throws {
        // Given
        let packagePath = try temporaryPath()
        let product = "my-product"
        let buildPath = try temporaryPath()
        let outputPath = try temporaryPath()

        system.succeedCommand([
            "swift", "build",
            "--configuration", "release",
            "--disable-sandbox",
            "--package-path", packagePath.pathString,
            "--product", product,
            "--build-path", buildPath.pathString,
            "--triple", "arm64-apple-macosx",
        ])
        system.succeedCommand([
            "swift", "build",
            "--configuration", "release",
            "--disable-sandbox",
            "--package-path", packagePath.pathString,
            "--product", product,
            "--build-path", buildPath.pathString,
            "--triple", "x86_64-apple-macosx",
        ])

        system.succeedCommand([
            "lipo", "-create", "-output", outputPath.appending(component: product).pathString,
            buildPath.appending(components: "arm64-apple-macosx", "release", product).pathString,
            buildPath.appending(components: "x86_64-apple-macosx", "release", product).pathString,
        ])

        // When
        try subject.buildFatReleaseBinary(
            packagePath: packagePath,
            product: product,
            buildPath: buildPath,
            outputPath: outputPath
        )

        // Then
        // Assert that `outputPath` was created
        XCTAssertTrue(fileHandler.isFolder(outputPath))
    }
}
