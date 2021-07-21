import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
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
}
