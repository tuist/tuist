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
    private var carthage: MockCarthage!

    override func setUp() {
        super.setUp()

        carthageController = MockCarthageController()
        carthage = MockCarthage()
        subject = CarthageInteractor(
            carthageController: carthageController,
            carthage: carthage
        )
    }

    override func tearDown() {
        carthageController = nil
        carthage = nil
        subject = nil

        super.tearDown()
    }

    func test_fetch() throws {
        // Given
        carthageController.canUseSystemCarthageStub = { true }

        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<Platform> = [.iOS, .watchOS, .macOS, .tvOS]
        let options = Set<CarthageDependencies.Options>([])
        let stubbedDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
            ],
            options: options
        )

        carthage.bootstrapStub = { [unowned self] parameters in
            XCTAssertEqual(parameters.path, try self.temporaryPath())
            XCTAssertEqual(parameters.platforms, platforms)
            XCTAssertEqual(parameters.options, options)

            try self.simulateCarthageOutput(at: parameters.path)
        }

        // When
        try subject.fetch(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: stubbedDependencies,
            platforms: platforms
        )

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
            options: []
        )
        let platforms: Set<Platform> = [.iOS]

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.fetch(
                dependenciesDirectory: dependenciesDirectory,
                dependencies: dependencies,
                platforms: platforms
            ),
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
            options: [.useXCFrameworks]
        )
        let platforms: Set<Platform> = [.iOS]

        XCTAssertThrowsSpecific(
            try subject.fetch(
                dependenciesDirectory: dependenciesDirectory,
                dependencies: dependencies,
                platforms: platforms
            ),
            CarthageInteractorError.xcFrameworksProductionNotSupported
        )
    }

    func test_update() throws {
        // Given
        carthageController.canUseSystemCarthageStub = { true }

        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<Platform> = [.iOS, .watchOS, .macOS, .tvOS]
        let options = Set<CarthageDependencies.Options>([])
        let stubbedDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
            ],
            options: options
        )

        carthage.updateStub = { [unowned self] parameters in
            XCTAssertEqual(parameters.path, try self.temporaryPath())
            XCTAssertEqual(parameters.platforms, platforms)
            XCTAssertEqual(parameters.options, options)

            try self.simulateCarthageOutput(at: parameters.path)
        }

        // When
        try subject.update(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: stubbedDependencies,
            platforms: platforms
        )

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
    }

    func test_update_throws_when_carthageUnavailableInEnvironment() throws {
        // Given
        carthageController.canUseSystemCarthageStub = { false }

        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let dependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
            ],
            options: []
        )
        let platforms: Set<Platform> = [.iOS]

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.update(
                dependenciesDirectory: dependenciesDirectory,
                dependencies: dependencies,
                platforms: platforms
            ),
            CarthageInteractorError.carthageNotFound
        )
    }

    func test_update_throws_when_xcFrameworkdProductionUnsupported_and_useXCFrameworksSpecifiedInOptions() throws {
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
            options: [.useXCFrameworks]
        )
        let platforms: Set<Platform> = [.iOS]

        XCTAssertThrowsSpecific(
            try subject.update(
                dependenciesDirectory: dependenciesDirectory,
                dependencies: dependencies,
                platforms: platforms
            ),
            CarthageInteractorError.xcFrameworksProductionNotSupported
        )
    }

    func test_clean() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let lockfilesDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)

        try createFiles([
            "Dependencies/Lockfiles/Cartfile.resolved",
            "Dependencies/Lockfiles/OtherLockfile.lock",
            "Dependencies/Carthage/Info.plist",
            "Dependencies/OtherDepedenciesManager/bar.bar",
        ])

        // When
        try subject.clean(dependenciesDirectory: dependenciesDirectory)

        // Then
        XCTAssertEqual(
            try fileHandler.contentsOfDirectory(dependenciesDirectory).sorted(),
            [
                lockfilesDirectory,
                dependenciesDirectory.appending(component: "OtherDepedenciesManager"),
            ].sorted()
        )
        XCTAssertEqual(
            try fileHandler.contentsOfDirectory(lockfilesDirectory).sorted(),
            [
                lockfilesDirectory.appending(component: "OtherLockfile.lock"),
            ].sorted()
        )
    }
}

// MARK: - Helpers

private extension CarthageInteractorTests {
    func simulateCarthageOutput(at path: AbsolutePath) throws {
        try [
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
        ].forEach {
            try fileHandler.touch(path.appending(RelativePath($0)))
        }
    }
}
