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
    private var carthageGraphGenerator: MockCarthageGraphGenerator!

    override func setUp() {
        super.setUp()

        carthageController = MockCarthageController()
        carthageGraphGenerator = MockCarthageGraphGenerator()
        subject = CarthageInteractor(
            carthageController: carthageController,
            carthageGraphGenerator: carthageGraphGenerator
        )
    }

    override func tearDown() {
        carthageController = nil
        carthageGraphGenerator = nil
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
        let carthageBuildDirectory = carthageDirectory
            .appending(component: "Build")

        let platforms: Set<Platform> = [.iOS, .watchOS, .macOS, .tvOS]
        let stubbedDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
            ]
        )

        carthageController.bootstrapStub = { arg0, arg1, arg2 in
            XCTAssertEqual(arg0, dependenciesDirectory)
            XCTAssertEqual(arg1, platforms)
            XCTAssertTrue(arg2)

            try self.simulateCarthageOutput(at: arg0)
        }
        carthageGraphGenerator.generateStub = { arg0 in
            XCTAssertEqual(arg0, carthageDirectory.appending(component: "Build"))
            return .test()
        }

        // When
        let got = try subject.install(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: stubbedDependencies,
            platforms: platforms,
            shouldUpdate: false
        )

        // Then
        XCTAssertEqual(got, .test())
        XCTAssertTrue(carthageGraphGenerator.invokedGenerate)

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
                "Build",
                "Cartfile",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageBuildDirectory,
            [
                "iOS",
                "Mac",
                "watchOS",
                "tvOS",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageBuildDirectory.appending(component: "iOS"),
            [
                "Moya.framework",
                "ReactiveMoya.framework",
                "RxMoya.framework",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageBuildDirectory.appending(component: "Mac"),
            [
                "Moya.framework",
                "ReactiveMoya.framework",
                "RxMoya.framework",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageBuildDirectory.appending(component: "watchOS"),
            [
                "Moya.framework",
                "ReactiveMoya.framework",
                "RxMoya.framework",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageBuildDirectory.appending(component: "tvOS"),
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
        let carthageBuildDirectory = carthageDirectory
            .appending(component: "Build")

        let platforms: Set<Platform> = [.iOS, .watchOS, .macOS, .tvOS]
        let stubbedDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
            ]
        )

        carthageController.updateStub = { arg0, arg1, arg2 in
            XCTAssertEqual(arg0, dependenciesDirectory)
            XCTAssertEqual(arg1, platforms)
            XCTAssertTrue(arg2)

            try self.simulateCarthageOutput(at: arg0)
        }
        carthageGraphGenerator.generateStub = { arg0 in
            XCTAssertEqual(arg0, carthageDirectory.appending(component: "Build"))
            return .test()
        }

        // When
        let got = try subject.install(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: stubbedDependencies,
            platforms: platforms,
            shouldUpdate: true
        )

        // Then
        XCTAssertEqual(got, .test())
        XCTAssertTrue(carthageGraphGenerator.invokedGenerate)

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
                "Build",
                "Cartfile",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageBuildDirectory,
            [
                "iOS",
                "Mac",
                "watchOS",
                "tvOS",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageBuildDirectory.appending(component: "iOS"),
            [
                "Moya.framework",
                "ReactiveMoya.framework",
                "RxMoya.framework",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageBuildDirectory.appending(component: "Mac"),
            [
                "Moya.framework",
                "ReactiveMoya.framework",
                "RxMoya.framework",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageBuildDirectory.appending(component: "watchOS"),
            [
                "Moya.framework",
                "ReactiveMoya.framework",
                "RxMoya.framework",
            ]
        )
        try XCTAssertDirectoryContentEqual(
            carthageBuildDirectory.appending(component: "tvOS"),
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
            ]
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
            "Dependencies/OtherDependenciesManager/bar.bar",
        ])

        // When
        try subject.clean(dependenciesDirectory: dependenciesDirectory)

        // Then
        try XCTAssertDirectoryContentEqual(
            dependenciesDirectory,
            [
                Constants.DependenciesDirectory.lockfilesDirectoryName,
                "OtherDependenciesManager",
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

extension CarthageInteractorTests {
    private func simulateCarthageOutput(at path: AbsolutePath) throws {
        try [
            "Cartfile.resolved",
            "Carthage/Cartfile",
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
