import FileSystem
import FileSystemTesting
import TSCUtility
import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistLoader

struct PackageInfoLoaderTests {
    private let subject: PackageInfoLoader
    private let system = MockSystem()
    private let fileSystem = FileSystem()

    init() {
        subject = PackageInfoLoader(
            system: system,
            fileSystem: fileSystem
        )
    }

    @Test(.inTemporaryDirectory) func loadPackageInfo() throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        system.succeedCommand(
            ["swift", "package", "--package-path", path.pathString, "--disable-sandbox", "dump-package"],
            output: PackageInfo.testJSON
        )

        let packageInfo = try subject.loadPackageInfo(at: path, disableSandbox: true)
        #expect(packageInfo == PackageInfo.test)
    }

    @Test(.inTemporaryDirectory) func loadPackageInfo_Xcode14() throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        system.succeedCommand(
            ["swift", "package", "--package-path", path.pathString, "--disable-sandbox", "dump-package"],
            output: PackageInfo.testJSONXcode14
        )

        let packageInfo = try subject.loadPackageInfo(at: path, disableSandbox: true)
        #expect(packageInfo == PackageInfo.test)
    }

    @Test(.inTemporaryDirectory) func loadPackageInfo_alamofire() throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        system.succeedCommand(
            ["swift", "package", "--package-path", path.pathString, "--disable-sandbox", "dump-package"],
            output: PackageInfo.alamofireJSON
        )

        let packageInfo = try subject.loadPackageInfo(at: path, disableSandbox: true)
        #expect(packageInfo == PackageInfo.alamofire)
    }

    @Test(.inTemporaryDirectory) func loadPackageInfo_googleAppMeasurement() throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        system.succeedCommand(
            ["swift", "package", "--package-path", path.pathString, "--disable-sandbox", "dump-package"],
            output: PackageInfo.googleAppMeasurementJSON
        )

        let packageInfo = try subject.loadPackageInfo(at: path, disableSandbox: true)
        #expect(packageInfo == PackageInfo.googleAppMeasurement)
    }
}
