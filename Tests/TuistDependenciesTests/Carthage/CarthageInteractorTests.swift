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

    private var carthageController: MockCarthageController!
    private var carthageCommandGenerator: MockCarthageCommandGenerator!

    override func setUp() {
        super.setUp()

        carthageController = MockCarthageController()
        carthageCommandGenerator = MockCarthageCommandGenerator()

        subject = CarthageInteractor(
            carthageController: carthageController,
            carthageCommandGenerator: carthageCommandGenerator
        )
    }

    override func tearDown() {
        carthageController = nil
        carthageCommandGenerator = nil

        subject = nil

        super.tearDown()
    }

    func test_fetch_throws_when_carthageUnavailableInEnvironment() throws {
        // Given
        carthageController.canUseSystemCarthageStub = { false }

        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let dependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
            ],
            platforms: [.iOS],
            options: []
        )

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.fetch(dependenciesDirectory: dependenciesDirectory, dependencies: dependencies),
            CarthageInteractorError.carthageNotFound
        )
    }

    func test_fetch_throws_when_xcFrameworkdProductionUnsupported_and_useXCFrameworksSpecifiedInOptions() throws {
        // Given
        carthageController.canUseSystemCarthageStub = { true }
        carthageController.isXCFrameworksProductionSupportedStub = { false }

        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let dependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
            ],
            platforms: [.iOS],
            options: [.useXCFrameworks]
        )

        XCTAssertThrowsSpecific(
            try subject.fetch(dependenciesDirectory: dependenciesDirectory, dependencies: dependencies),
            CarthageInteractorError.xcFrameworksProductionNotSupported
        )
    }

    func test_fetch_allPlatforms() throws {
        // Given
        carthageController.canUseSystemCarthageStub = { true }
        
        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)

        try createFiles([
            "Cartfile.resolved",
            "Carthage/Build/iOS/Moya.framework/Info.plist",
            "Carthage/Build/iOS/ReactiveMoya.framework/Info.plist",
            "Carthage/Build/iOS/RxMoya.framework/Info.plist",
            "Carthage/Build/Mac/Moya.framework/Info.plist",
            "Carthage/Build/Mac/ReactiveMoya.framework/Info.plist",
            "Carthage/Build/Mac/RxMoya.framework/Info.plist",
            "Carthage/Build/watchOS/Moya.framework/Info.plist",
            "Carthage/Build/watchOS/ReactiveMoya.framework/Info.plist",
            "Carthage/Build/watchOS/RxMoya.framework/Info.plist",
            "Carthage/Build/tvOS/Moya.framework/Info.plist",
            "Carthage/Build/tvOS/ReactiveMoya.framework/Info.plist",
            "Carthage/Build/tvOS/RxMoya.framework/Info.plist",
        ])

        let platforms = Set<Platform>([.iOS, .watchOS, .macOS, .tvOS])
        let options = Set<CarthageDependencies.Options>([])
        let stubbedDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
            ],
            platforms: platforms,
            options: options
        )
        let stubbedCommand = ["carthage", "bootstrap", "--project-directory", try temporaryPath().pathString, "--platform iOS,macOS,tvOS,watchOS", "--cache-builds", "--new-resolver"]

        carthageCommandGenerator.commandStub = { _ in stubbedCommand }

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
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.path, try temporaryPath())
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.platforms, platforms)
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.options, options)
    }

    func test_fetch_onePlatform() throws {
        // Given
        carthageController.canUseSystemCarthageStub = { true }
        
        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)

        try createFiles([
            "Cartfile.resolved",
            "Carthage/Build/iOS/Moya.framework/Info.plist",
            "Carthage/Build/iOS/ReactiveMoya.framework/Info.plist",
            "Carthage/Build/iOS/RxMoya.framework/Info.plist",
        ])

        let platforms = Set<Platform>([.iOS])
        let options = Set<CarthageDependencies.Options>([])
        let stubbedDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
            ],
            platforms: platforms,
            options: options
        )
        let stubbedCommand = ["carthage", "bootstrap", "--project-directory", try temporaryPath().pathString, "--platform iOS", "--cache-builds", "--new-resolver"]

        carthageCommandGenerator.commandStub = { _ in stubbedCommand }

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
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.path, try temporaryPath())
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.platforms, platforms)
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.options, options)
    }
}
