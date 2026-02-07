import Mockable
import Path
import TSCUtility
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest
@testable import TuistLoader

final class PackageInfoLoaderTests: TuistUnitTestCase {
    private var subject: PackageInfoLoader!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var swiftVersionProvider: MockSwiftVersionProviding!
    private var cacheDirectory: AbsolutePath!

    override func setUp() {
        super.setUp()

        cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        swiftVersionProvider = MockSwiftVersionProviding()
        cacheDirectory = try! temporaryPath().appending(component: "Cache")

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.packageInfo))
            .willReturn(cacheDirectory)
        given(swiftVersionProvider)
            .swiftlangVersion()
            .willReturn("5.9.0.0")
        given(swiftVersionProvider)
            .swiftVersion()
            .willReturn("5.9")

        subject = PackageInfoLoader(
            system: system,
            fileSystem: fileSystem,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            swiftVersionProvider: swiftVersionProvider,
            tuistVersion: "1.0.0",
            fileHandler: fileHandler
        )
    }

    override func tearDown() {
        subject = nil
        cacheDirectoriesProvider = nil
        swiftVersionProvider = nil
        cacheDirectory = nil

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
                "--disable-sandbox",
                "dump-package",
            ],
            output: PackageInfo.testJSON
        )

        // When
        let packageInfo = try subject.loadPackageInfo(at: path, disableSandbox: true)

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
                "--disable-sandbox",
                "dump-package",
            ],
            output: PackageInfo.testJSONXcode14
        )

        // When
        let packageInfo = try subject.loadPackageInfo(at: path, disableSandbox: true)

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
                "--disable-sandbox",
                "dump-package",
            ],
            output: PackageInfo.alamofireJSON
        )

        // When
        let packageInfo = try subject.loadPackageInfo(at: path, disableSandbox: true)

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
                "--disable-sandbox",
                "dump-package",
            ],
            output: PackageInfo.googleAppMeasurementJSON
        )

        // When
        let packageInfo = try subject.loadPackageInfo(at: path, disableSandbox: true)

        // Then
        XCTAssertEqual(packageInfo, PackageInfo.googleAppMeasurement)
    }

    func test_loadPackageInfo_usesCacheOnSecondLoad() throws {
        // Given
        let path = try temporaryPath()
        let manifestPath = path.appending(component: "Package.swift")
        try fileHandler.write(
            """
            // swift-tools-version: 5.9
            import PackageDescription

            let package = Package(name: "App")
            """,
            path: manifestPath,
            atomically: true
        )

        let command = [
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "--disable-sandbox",
            "dump-package",
        ]
        system.succeedCommand(command, output: PackageInfo.testJSON)

        // When
        let first = try subject.loadPackageInfo(at: path, disableSandbox: true)
        let second = try subject.loadPackageInfo(at: path, disableSandbox: true)

        // Then
        XCTAssertBetterEqual(first, PackageInfo.test)
        XCTAssertBetterEqual(second, PackageInfo.test)
        XCTAssertEqual(system.calls.filter { $0 == command.joined(separator: " ") }.count, 1)
    }

    func test_loadPackageInfo_resolvedChangeInvalidatesCache() throws {
        // Given
        let path = try temporaryPath()
        let manifestPath = path.appending(component: "Package.swift")
        let resolvedPath = path.appending(component: "Package.resolved")
        try fileHandler.write(
            """
            // swift-tools-version: 5.9
            import PackageDescription

            let package = Package(name: "App")
            """,
            path: manifestPath,
            atomically: true
        )
        try fileHandler.write("{\"version\":1}", path: resolvedPath, atomically: true)

        let command = [
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "--disable-sandbox",
            "dump-package",
        ]
        system.succeedCommand(command, output: PackageInfo.testJSON)

        // When
        _ = try subject.loadPackageInfo(at: path, disableSandbox: true)
        try fileHandler.write("{\"version\":2}", path: resolvedPath, atomically: true)
        _ = try subject.loadPackageInfo(at: path, disableSandbox: true)

        // Then
        XCTAssertEqual(system.calls.filter { $0 == command.joined(separator: " ") }.count, 2)
    }
}
