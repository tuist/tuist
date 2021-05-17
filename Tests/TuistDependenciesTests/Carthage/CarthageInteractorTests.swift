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

    override func setUp() {
        super.setUp()

        carthageController = MockCarthageController()
        subject = CarthageInteractor(
            carthageController: carthageController
        )
    }

    override func tearDown() {
        carthageController = nil
        subject = nil

        super.tearDown()
    }

    func test_install_when_shouldNotBeUpdated() throws {
        // Given
        carthageController.canUseSystemCarthageStub = { true }

        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let lockfilesDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
        let carthageDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)

        let platforms: Set<Platform> = [.iOS, .watchOS, .macOS, .tvOS]
        let options = Set<CarthageDependencies.Options>([])
        let stubbedDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
            ],
            options: options
        )

        carthageController.bootstrapStub = { arg0, arg1, arg2 in
            XCTAssertEqual(arg0, try self.temporaryPath())
            XCTAssertEqual(arg1, platforms)
            XCTAssertEqual(arg2, options)

            try self.simulateCarthageOutput(at: arg0)
        }

        // When
        try subject.install(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: stubbedDependencies,
            platforms: platforms,
            shouldUpdate: false
        )

        // Then
        try XCTAssertDirectoryContentEqual(
            dependenciesDirectory,
            [
                Constants.DependenciesDirectory.lockfilesDirectoryName,
                Constants.DependenciesDirectory.carthageDirectoryName,
            ]
        )
        try XCTAssertDirectoryContentEqual(
            lockfilesDirectory,
            [
                Constants.DependenciesDirectory.cartfileResolvedName,
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageDirectory,
            [
                "iOS",
                "Mac",
                "watchOS",
                "tvOS",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageDirectory.appending(component: "iOS"),
            [
                "Moya.framework",
                "ReactiveMoya.framework",
                "RxMoya.framework",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageDirectory.appending(component: "Mac"),
            [
                "Moya.framework",
                "ReactiveMoya.framework",
                "RxMoya.framework",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageDirectory.appending(component: "watchOS"),
            [
                "Moya.framework",
                "ReactiveMoya.framework",
                "RxMoya.framework",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageDirectory.appending(component: "tvOS"),
            [
                "Moya.framework",
                "ReactiveMoya.framework",
                "RxMoya.framework",
            ]
        )
    }

    func test_install_when_shouldBeUpdated() throws {
        // Given
        carthageController.canUseSystemCarthageStub = { true }

        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let lockfilesDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
        let carthageDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)

        let platforms: Set<Platform> = [.iOS, .watchOS, .macOS, .tvOS]
        let options = Set<CarthageDependencies.Options>([])
        let stubbedDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
            ],
            options: options
        )

        carthageController.updateStub = { arg0, arg1, arg2 in
            XCTAssertEqual(arg0, try self.temporaryPath())
            XCTAssertEqual(arg1, platforms)
            XCTAssertEqual(arg2, options)

            try self.simulateCarthageOutput(at: arg0)
        }

        // When
        try subject.install(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: stubbedDependencies,
            platforms: platforms,
            shouldUpdate: true
        )

        // Then
        try XCTAssertDirectoryContentEqual(
            dependenciesDirectory,
            [
                Constants.DependenciesDirectory.lockfilesDirectoryName,
                Constants.DependenciesDirectory.carthageDirectoryName,
            ]
        )
        try XCTAssertDirectoryContentEqual(
            lockfilesDirectory,
            [
                Constants.DependenciesDirectory.cartfileResolvedName,
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageDirectory,
            [
                "iOS",
                "Mac",
                "watchOS",
                "tvOS",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageDirectory.appending(component: "iOS"),
            [
                "Moya.framework",
                "ReactiveMoya.framework",
                "RxMoya.framework",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageDirectory.appending(component: "Mac"),
            [
                "Moya.framework",
                "ReactiveMoya.framework",
                "RxMoya.framework",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageDirectory.appending(component: "watchOS"),
            [
                "Moya.framework",
                "ReactiveMoya.framework",
                "RxMoya.framework",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageDirectory.appending(component: "tvOS"),
            [
                "Moya.framework",
                "ReactiveMoya.framework",
                "RxMoya.framework",
            ]
        )
    }

    func test_install_throws_when_carthageUnavailableInEnvironment() throws {
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
            try subject.install(
                dependenciesDirectory: dependenciesDirectory,
                dependencies: dependencies,
                platforms: platforms,
                shouldUpdate: true
            ),
            CarthageInteractorError.carthageNotFound
        )
    }

    func test_install_throws_when_xcFrameworkdProductionUnsupported_and_useXCFrameworksSpecifiedInOptions() throws {
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

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.install(
                dependenciesDirectory: dependenciesDirectory,
                dependencies: dependencies,
                platforms: platforms,
                shouldUpdate: true
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
        try XCTAssertDirectoryContentEqual(
            dependenciesDirectory,
            [
                Constants.DependenciesDirectory.lockfilesDirectoryName,
                "OtherDepedenciesManager",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            lockfilesDirectory,
            [
                "OtherLockfile.lock",
            ]
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
