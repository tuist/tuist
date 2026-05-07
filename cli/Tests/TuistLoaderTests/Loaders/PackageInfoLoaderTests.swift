import TSCUtility
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest
@testable import TuistLoader

final class PackageInfoLoaderTests: TuistUnitTestCase {
    private var subject: PackageInfoLoader!

    override func setUp() {
        super.setUp()

        subject = PackageInfoLoader(
            commandRunner: mockCommandRunner,
            fileSystem: fileSystem
        )
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func test_loadPackageInfo() async throws {
        // Given
        let path = try temporaryPath()
        mockCommandRunner.succeedCommand(
            [
                "swift",
                "package",
                "--package-path",
                path.pathString,
                "--disable-sandbox",
                "dump-package",
            ],
            output: PackageInfo.testJSON
        )

        // When
        let packageInfo = try await subject.loadPackageInfo(at: path, disableSandbox: true)

        // Then
        XCTAssertBetterEqual(packageInfo, PackageInfo.test)
    }

    func test_loadPackageInfo_Xcode14() async throws {
        // Given
        let path = try temporaryPath()
        mockCommandRunner.succeedCommand(
            [
                "swift",
                "package",
                "--package-path",
                path.pathString,
                "--disable-sandbox",
                "dump-package",
            ],
            output: PackageInfo.testJSONXcode14
        )

        // When
        let packageInfo = try await subject.loadPackageInfo(at: path, disableSandbox: true)

        // Then
        XCTAssertEqual(packageInfo, PackageInfo.test)
    }

    func test_loadPackageInfo_alamofire() async throws {
        // Given
        let path = try temporaryPath()
        mockCommandRunner.succeedCommand(
            [
                "swift",
                "package",
                "--package-path",
                path.pathString,
                "--disable-sandbox",
                "dump-package",
            ],
            output: PackageInfo.alamofireJSON
        )

        // When
        let packageInfo = try await subject.loadPackageInfo(at: path, disableSandbox: true)

        // Then
        XCTAssertEqual(packageInfo, PackageInfo.alamofire)
    }

    func test_loadPackageInfo_googleAppMeasurement() async throws {
        // Given
        let path = try temporaryPath()
        mockCommandRunner.succeedCommand(
            [
                "swift",
                "package",
                "--package-path",
                path.pathString,
                "--disable-sandbox",
                "dump-package",
            ],
            output: PackageInfo.googleAppMeasurementJSON
        )

        // When
        let packageInfo = try await subject.loadPackageInfo(at: path, disableSandbox: true)

        // Then
        XCTAssertEqual(packageInfo, PackageInfo.googleAppMeasurement)
    }
}
