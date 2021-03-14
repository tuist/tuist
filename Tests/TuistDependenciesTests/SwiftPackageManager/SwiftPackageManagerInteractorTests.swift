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

    private var fileHandlerMock: MockFileHandler!

    private var temporaryDirectoryPath: AbsolutePath!

    override func setUp() {
        super.setUp()

        do {
            temporaryDirectoryPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        } catch {
            XCTFail("Failed to setup TemporaryDirectory")
        }

        fileHandlerMock = MockFileHandler(temporaryDirectory: { self.temporaryDirectoryPath })

        subject = SwiftPackageManagerInteractor(
            fileHandler: fileHandlerMock
        )
    }

    override func tearDown() {
        fileHandlerMock = nil

        temporaryDirectoryPath = nil

        subject = nil

        super.tearDown()
    }

    func test_fetch() throws {
        // Given
        let temporaryPackageResolvedPath = temporaryDirectoryPath
            .appending(component: Constants.DependenciesDirectory.packageResolvedName)
        let temporaryBuildDirectory = temporaryDirectoryPath
            .appending(component: ".build")

        let rootPath = try temporaryPath()
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)

        try fileHandler.touch(temporaryPackageResolvedPath)
        try fileHandler.touch(temporaryBuildDirectory.appending(component: "manifest.db"))
        try fileHandler.touch(temporaryBuildDirectory.appending(component: "workspace-state.json"))
        try fileHandler.touch(temporaryBuildDirectory.appending(components: "artifacts", "foo.txt"))
        try fileHandler.touch(temporaryBuildDirectory.appending(components: "checkouts", "Alamofire", "Info.plist"))
        try fileHandler.touch(temporaryBuildDirectory.appending(components: "repositories", "checkouts-state.json"))
        try fileHandler.touch(temporaryBuildDirectory.appending(components: "repositories", "Alamofire-e8f130fe", "config"))

        let command = ["swift", "package", "--package-path", "\(temporaryDirectoryPath.pathString)", "resolve"]
        system.succeedCommand(command)

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
