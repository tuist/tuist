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
    private var swiftPackageManagerController: MockSwiftPackageManagerController!
    private var swiftPackageManagerGraphGenerator: MockSwiftPackageManagerGraphGenerator!

    override func setUp() {
        super.setUp()

        swiftPackageManagerController = MockSwiftPackageManagerController()
        swiftPackageManagerGraphGenerator = MockSwiftPackageManagerGraphGenerator()
        subject = SwiftPackageManagerInteractor(
            swiftPackageManagerController: swiftPackageManagerController,
            swiftPackageManagerGraphGenerator: swiftPackageManagerGraphGenerator
        )
    }

    override func tearDown() {
        subject = nil
        swiftPackageManagerController = nil

        super.tearDown()
    }

    func test_install_when_shouldNotBeUpdated() throws {
        // Given
        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let lockfilesDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
        let swiftPackageManagerDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)

        let dependencies = SwiftPackageManagerDependencies(
            [
                .remote(url: "https://github.com/Alamofire/Alamofire.git", requirement: .upToNextMajor("5.2.0")),
            ]
        )

        swiftPackageManagerController.resolveStub = { path in
            XCTAssertEqual(path, try self.temporaryPath())
            try self.simulateSPMOutput(at: path)
        }
        swiftPackageManagerController.setToolsVersionStub = { path, version in
            XCTAssertEqual(path, try self.temporaryPath())
            XCTAssertNil(version) // swift-tools-version is not specified
        }

        swiftPackageManagerGraphGenerator.generateStub = { path, platforms in
            XCTAssertEqual(path, dependenciesDirectory.appending(component: "SwiftPackageManager"))
            XCTAssertEqual(platforms, [.iOS])
            return .test()
        }

        // When
        let dependenciesGraph = try subject.install(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: dependencies,
            platforms: [.iOS],
            shouldUpdate: false,
            swiftToolsVersion: nil
        )

        // Then
        XCTAssertEqual(dependenciesGraph, .test())
        try XCTAssertDirectoryContentEqual(
            dependenciesDirectory,
            [
                Constants.DependenciesDirectory.lockfilesDirectoryName,
                Constants.DependenciesDirectory.swiftPackageManagerDirectoryName,
            ]
        )
        try XCTAssertDirectoryContentEqual(
            lockfilesDirectory,
            [
                Constants.DependenciesDirectory.packageResolvedName,
            ]
        )
        try XCTAssertDirectoryContentEqual(
            swiftPackageManagerDirectory,
            [
                "manifest.db",
                "workspace-state.json",
                "artifacts",
                "checkouts",
                "repositories",
            ]
        )

        XCTAssertTrue(swiftPackageManagerController.invokedResolve)
        XCTAssertTrue(swiftPackageManagerController.invokedSetToolsVersion)
        XCTAssertFalse(swiftPackageManagerController.invokedUpdate)
    }

    func test_install_when_shouldNotBeUpdated_and_swiftToolsVersionPassed() throws {
        // Given
        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let lockfilesDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
        let swiftPackageManagerDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)

        let swiftToolsVersion = "5.3.0"
        let dependencies = SwiftPackageManagerDependencies(
            [
                .remote(url: "https://github.com/Alamofire/Alamofire.git", requirement: .upToNextMajor("5.2.0")),
            ]
        )

        swiftPackageManagerController.resolveStub = { path in
            XCTAssertEqual(path, try self.temporaryPath())
            try self.simulateSPMOutput(at: path)
        }
        swiftPackageManagerController.setToolsVersionStub = { path, version in
            XCTAssertEqual(path, try self.temporaryPath())
            XCTAssertEqual(version, swiftToolsVersion) // version should be equal to the version that has been specified
        }

        swiftPackageManagerGraphGenerator.generateStub = { path, platforms in
            XCTAssertEqual(path, dependenciesDirectory.appending(component: "SwiftPackageManager"))
            XCTAssertEqual(platforms, [.iOS])
            return .test()
        }

        // When
        let dependenciesGraph = try subject.install(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: dependencies,
            platforms: [.iOS],
            shouldUpdate: false,
            swiftToolsVersion: swiftToolsVersion
        )

        // Then
        XCTAssertEqual(dependenciesGraph, .test())
        try XCTAssertDirectoryContentEqual(
            dependenciesDirectory,
            [
                Constants.DependenciesDirectory.lockfilesDirectoryName,
                Constants.DependenciesDirectory.swiftPackageManagerDirectoryName,
            ]
        )
        try XCTAssertDirectoryContentEqual(
            lockfilesDirectory,
            [
                Constants.DependenciesDirectory.packageResolvedName,
            ]
        )
        try XCTAssertDirectoryContentEqual(
            swiftPackageManagerDirectory,
            [
                "manifest.db",
                "workspace-state.json",
                "artifacts",
                "checkouts",
                "repositories",
            ]
        )

        XCTAssertTrue(swiftPackageManagerController.invokedResolve)
        XCTAssertTrue(swiftPackageManagerController.invokedSetToolsVersion)
        XCTAssertFalse(swiftPackageManagerController.invokedUpdate)
    }

    func test_install_when_shouldBeUpdated() throws {
        // Given
        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let lockfilesDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
        let swiftPackageManagerDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)

        let dependencies = SwiftPackageManagerDependencies(
            [
                .remote(url: "https://github.com/Alamofire/Alamofire.git", requirement: .upToNextMajor("5.2.0")),
            ]
        )

        swiftPackageManagerController.updateStub = { path in
            XCTAssertEqual(path, try self.temporaryPath())
            try self.simulateSPMOutput(at: path)
        }
        swiftPackageManagerController.setToolsVersionStub = { path, version in
            XCTAssertEqual(path, try self.temporaryPath())
            XCTAssertNil(version) // swift-tools-version is not specified
        }

        swiftPackageManagerGraphGenerator.generateStub = { path, platforms in
            XCTAssertEqual(path, dependenciesDirectory.appending(component: "SwiftPackageManager"))
            XCTAssertEqual(platforms, [.iOS])
            return .test()
        }

        // When
        let dependenciesGraph = try subject.install(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: dependencies,
            platforms: [.iOS],
            shouldUpdate: true,
            swiftToolsVersion: nil
        )

        // Then
        XCTAssertEqual(dependenciesGraph, .test())
        try XCTAssertDirectoryContentEqual(
            dependenciesDirectory,
            [
                Constants.DependenciesDirectory.lockfilesDirectoryName,
                Constants.DependenciesDirectory.swiftPackageManagerDirectoryName,
            ]
        )
        try XCTAssertDirectoryContentEqual(
            lockfilesDirectory,
            [
                Constants.DependenciesDirectory.packageResolvedName,
            ]
        )
        try XCTAssertDirectoryContentEqual(
            swiftPackageManagerDirectory,
            [
                "manifest.db",
                "workspace-state.json",
                "artifacts",
                "checkouts",
                "repositories",
            ]
        )

        XCTAssertTrue(swiftPackageManagerController.invokedUpdate)
        XCTAssertTrue(swiftPackageManagerController.invokedSetToolsVersion)
        XCTAssertFalse(swiftPackageManagerController.invokedResolve)
    }

    func test_clean() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let lockfilesDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)

        try createFiles([
            "Dependencies/Lockfiles/Package.resolved",
            "Dependencies/Lockfiles/OtherLockfile.lock",
            "Dependencies/SwiftPackageManager/Info.plist",
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

        XCTAssertFalse(swiftPackageManagerController.invokedUpdate)
        XCTAssertFalse(swiftPackageManagerController.invokedSetToolsVersion)
        XCTAssertFalse(swiftPackageManagerController.invokedResolve)
    }
}

// MARK: - Helpers

private extension SwiftPackageManagerInteractorTests {
    func simulateSPMOutput(at path: AbsolutePath) throws {
        try [
            "Package.resolved",
            ".build/manifest.db",
            ".build/workspace-state.json",
            ".build/artifacts/foo.txt",
            ".build/checkouts/Alamofire/Info.plist",
            ".build/repositories/checkouts-state.json",
            ".build/repositories/Alamofire-e8f130fe/config",
        ].forEach {
            try fileHandler.touch(path.appending(RelativePath($0)))
        }
    }
}
