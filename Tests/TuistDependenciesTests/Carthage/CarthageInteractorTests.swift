import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class CarthageInteractorTests: TuistUnitTestCase {
    private var subject: CarthageInteractor!

    private var fileHandlerMock: MockFileHandler!
    private var carthageController: MockCarthageController!
    private var carthageCommandGenerator: MockCarthageCommandGenerator!

    private var temporaryDirectoryPath: AbsolutePath!

    override func setUp() {
        super.setUp()

        do {
            temporaryDirectoryPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        } catch {
            XCTFail("Failed to setup TemporaryDirectory")
        }

        fileHandlerMock = MockFileHandler(temporaryDirectory: { self.temporaryDirectoryPath })
        carthageController = MockCarthageController()
        carthageCommandGenerator = MockCarthageCommandGenerator()

        subject = CarthageInteractor(fileHandler: fileHandlerMock,
                                     carthageController: carthageController,
                                     carthageCommandGenerator: carthageCommandGenerator)
    }

    override func tearDown() {
        fileHandlerMock = nil
        carthageController = nil
        carthageCommandGenerator = nil

        temporaryDirectoryPath = nil

        subject = nil

        super.tearDown()
    }

    func test_fetch_carthageUnavailableInEnvironment() throws {
        // Given
        carthageController.canUseSystemCarthageStub = { false }

        let rootPath = try temporaryPath()
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let dependencies = CarthageDependencies(
            dependencies: [
                .github(path: "Moya", requirement: .exact("1.1.1"))
            ],
            options: .init(platforms: [.iOS], useXCFrameworks: false)
        )

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.fetch(dependenciesDirectory: dependenciesDirectory, dependencies: dependencies),
            CarthageInteractorError.carthageNotFound
        )
    }

    func test_fetch_allPlatforms() throws {
        // Given
        carthageController.canUseSystemCarthageStub = { true }

        let rootPath = try temporaryPath()
        let temporaryDependenciesDirectory = temporaryDirectoryPath
            .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)
            .appending(component: "Build")
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)

        try fileHandler.touch(temporaryDirectoryPath.appending(components: Constants.DependenciesDirectory.cartfileResolvedName))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "iOS", "Moya.framework", "Info.plist"))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "iOS", "ReactiveMoya.framework", "Info.plist"))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "iOS", "RxMoya.framework", "Info.plist"))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "Mac", "Moya.framework", "Info.plist"))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "Mac", "ReactiveMoya.framework", "Info.plist"))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "Mac", "RxMoya.framework", "Info.plist"))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "watchOS", "Moya.framework", "Info.plist"))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "watchOS", "ReactiveMoya.framework", "Info.plist"))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "watchOS", "RxMoya.framework", "Info.plist"))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "tvOS", "Moya.framework", "Info.plist"))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "tvOS", "ReactiveMoya.framework", "Info.plist"))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "tvOS", "RxMoya.framework", "Info.plist"))

        let stubbedDependencies = CarthageDependencies(
            dependencies: [
                .github(path: "Moya", requirement: .exact("1.1.1"))
            ],
            options: .init(platforms: [.iOS, .watchOS, .macOS, .tvOS], useXCFrameworks: false)
        )
        let stubbedCommand = ["carthage", "bootstrap", "--project-directory", temporaryDirectoryPath.pathString, "--platform iOS,macOS,tvOS,watchOS", "--cache-builds", "--new-resolver"]

        carthageCommandGenerator.commandStub = { _, _, _ in stubbedCommand }

        system.whichStub = { _ in "1.0.0" }
        system.succeedCommand(stubbedCommand)

        // When
        try subject.fetch(dependenciesDirectory: dependenciesDirectory, dependencies: stubbedDependencies)

        // Then
        let expectedCartfileResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
        let expectedCarthageDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)

        XCTAssertTrue(fileHandler.exists(expectedCartfileResolvedPath))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "iOS", "Moya.framework", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "iOS", "ReactiveMoya.framework", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "iOS", "RxMoya.framework", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "Mac", "Moya.framework", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "Mac", "ReactiveMoya.framework", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "Mac", "RxMoya.framework", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "watchOS", "Moya.framework", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "watchOS", "ReactiveMoya.framework", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "watchOS", "RxMoya.framework", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "tvOS", "Moya.framework", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "tvOS", "ReactiveMoya.framework", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "tvOS", "RxMoya.framework", "Info.plist")))

        XCTAssertTrue(carthageCommandGenerator.invokedCommand)
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.path, temporaryDirectoryPath)
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.platforms, [.iOS, .watchOS, .macOS, .tvOS])
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.produceXCFrameworks, false)
    }

    func test_fetch_onePlatform() throws {
        // Given
        carthageController.canUseSystemCarthageStub = { true }

        let rootPath = try temporaryPath()
        let temporaryDependenciesDirectory = temporaryDirectoryPath
            .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)
            .appending(component: "Build")
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)

        try fileHandler.touch(temporaryDirectoryPath.appending(components: Constants.DependenciesDirectory.cartfileResolvedName))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "iOS", "Moya.framework", "Info.plist"))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "iOS", "ReactiveMoya.framework", "Info.plist"))
        try fileHandler.touch(temporaryDependenciesDirectory.appending(components: "iOS", "RxMoya.framework", "Info.plist"))

        let stubbedDependencies = CarthageDependencies(
            dependencies: [
                .github(path: "Moya", requirement: .exact("1.1.1"))
            ],
            options: .init(platforms: [.iOS], useXCFrameworks: false)
        )
        let stubbedCommand = ["carthage", "bootstrap", "--project-directory", temporaryDirectoryPath.pathString, "--platform iOS", "--cache-builds", "--new-resolver"]

        carthageCommandGenerator.commandStub = { _, _, _ in stubbedCommand }

        system.whichStub = { _ in "1.0.0" }
        system.succeedCommand(stubbedCommand)

        // When
        try subject.fetch(dependenciesDirectory: dependenciesDirectory, dependencies: stubbedDependencies)

        // Then
        let expectedCartfileResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
        let expectedCarthageDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)

        XCTAssertTrue(fileHandler.exists(expectedCartfileResolvedPath))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "iOS", "Moya.framework", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "iOS", "ReactiveMoya.framework", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedCarthageDirectory.appending(components: "iOS", "RxMoya.framework", "Info.plist")))
        XCTAssertFalse(fileHandler.exists(expectedCarthageDirectory.appending(components: "Mac", "Moya.framework", "Info.plist")))
        XCTAssertFalse(fileHandler.exists(expectedCarthageDirectory.appending(components: "Mac", "ReactiveMoya.framework", "Info.plist")))
        XCTAssertFalse(fileHandler.exists(expectedCarthageDirectory.appending(components: "Mac", "RxMoya.framework", "Info.plist")))
        XCTAssertFalse(fileHandler.exists(expectedCarthageDirectory.appending(components: "watchOS", "Moya.framework", "Info.plist")))
        XCTAssertFalse(fileHandler.exists(expectedCarthageDirectory.appending(components: "watchOS", "ReactiveMoya.framework", "Info.plist")))
        XCTAssertFalse(fileHandler.exists(expectedCarthageDirectory.appending(components: "watchOS", "RxMoya.framework", "Info.plist")))
        XCTAssertFalse(fileHandler.exists(expectedCarthageDirectory.appending(components: "tvOS", "Moya.framework", "Info.plist")))
        XCTAssertFalse(fileHandler.exists(expectedCarthageDirectory.appending(components: "tvOS", "ReactiveMoya.framework", "Info.plist")))
        XCTAssertFalse(fileHandler.exists(expectedCarthageDirectory.appending(components: "tvOS", "RxMoya.framework", "Info.plist")))

        XCTAssertTrue(carthageCommandGenerator.invokedCommand)
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.path, temporaryDirectoryPath)
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.platforms, [.iOS])
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.produceXCFrameworks, false)
    }
}
