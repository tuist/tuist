import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class SwiftPackageManagerInteractorTests: TuistUnitTestCase {
    private var subject: SwiftPackageManagerInteractor!

    override func setUp() {
        super.setUp()

        subject = SwiftPackageManagerInteractor()
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func test_fetch() throws {
        // Given
        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)

        try createFiles([
            "Package.resolved",
            ".build/manifest.db",
            ".build/workspace-state.json",
            ".build/artifacts/foo.txt",
            ".build/checkouts/Alamofire/Info.plist",
            ".build/repositories/checkouts-state.json",
            ".build/repositories/Alamofire-e8f130fe/config",
        ])

        let command = ["swift", "package", "--package-path", "\(try temporaryPath().pathString)", "resolve"]
        system.succeedCommand(command)
        system.swiftVersionStub = { "5.3" }

        let depedencies = SwiftPackageManagerDependencies(
            [
                .remote(url: "https://github.com/Alamofire/Alamofire.git", requirement: .upToNextMajor("5.2.0")),
            ]
        )

        // When
        try subject.fetch(dependenciesDirectory: dependenciesDirectory, dependencies: depedencies)

        // Then
        let expectedPackageResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.packageResolvedName)
        let expectedBuildDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)
            .appending(component: ".build")

        XCTAssertTrue(fileHandler.exists(expectedPackageResolvedPath))
        XCTAssertTrue(fileHandler.exists(expectedBuildDirectory.appending(component: "manifest.db")))
        XCTAssertTrue(fileHandler.exists(expectedBuildDirectory.appending(component: "workspace-state.json")))
        XCTAssertTrue(fileHandler.exists(expectedBuildDirectory.appending(components: "artifacts", "foo.txt")))
        XCTAssertTrue(fileHandler.exists(expectedBuildDirectory.appending(components: "checkouts", "Alamofire", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedBuildDirectory.appending(components: "repositories", "checkouts-state.json")))
        XCTAssertTrue(fileHandler.exists(expectedBuildDirectory.appending(components: "repositories", "Alamofire-e8f130fe", "config")))
    }
}
