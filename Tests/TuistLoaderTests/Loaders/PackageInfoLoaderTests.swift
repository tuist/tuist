import Path
import TSCUtility
import TuistCore
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest
@testable import TuistLoader

final class PackageInfoLoaderTests: TuistUnitTestCase {
    private var subject: PackageInfoLoader!

    override func setUp() {
        super.setUp()

        subject = PackageInfoLoader(
            system: system,
            fileHandler: fileHandler
        )
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
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
        XCTAssertBetterEqual(packageInfo, PackageInfo.test)
    }

    func test_loadPackageInfo_Xcode14() throws {
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
            output: PackageInfo.testJSONXcode14
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
