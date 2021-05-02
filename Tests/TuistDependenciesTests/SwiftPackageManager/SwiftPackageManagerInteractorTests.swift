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
    private var swiftPackageManager: MockSwiftPackageManager!

    override func setUp() {
        super.setUp()

        swiftPackageManager = MockSwiftPackageManager()
        subject = SwiftPackageManagerInteractor(
            swiftPackageManager: swiftPackageManager
        )
    }

    override func tearDown() {
        subject = nil
        swiftPackageManager = nil

        super.tearDown()
    }

    func test_fetch() throws {
        // Given
        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let lockfilesDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
        let swiftPackageManagerDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)

        let depedencies = SwiftPackageManagerDependencies([
            .remote(url: "https://github.com/Alamofire/Alamofire.git", requirement: .upToNextMajor("5.2.0")),
        ])

        swiftPackageManager.resolveStub = { path in
            XCTAssertEqual(path, try self.temporaryPath())

            try self.simulateSPMOutput(at: path)
        }

        // When
        try subject.fetch(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: depedencies
        )

        // Then
        XCTAssertDirectoryContentEqual(
            dependenciesDirectory,
            [
                Constants.DependenciesDirectory.lockfilesDirectoryName,
                Constants.DependenciesDirectory.swiftPackageManagerDirectoryName,
            ]
        )
        XCTAssertDirectoryContentEqual(
            lockfilesDirectory,
            [
                Constants.DependenciesDirectory.packageResolvedName,
            ]
        )
        XCTAssertDirectoryContentEqual(
            swiftPackageManagerDirectory,
            [
                "manifest.db",
                "workspace-state.json",
                "artifacts",
                "checkouts",
                "repositories",
            ]
        )
    }

    func test_update() throws {
        // Given
        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let lockfilesDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
        let swiftPackageManagerDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)

        let depedencies = SwiftPackageManagerDependencies([
            .remote(url: "https://github.com/Alamofire/Alamofire.git", requirement: .upToNextMajor("5.2.0")),
        ])

        swiftPackageManager.updateStub = { path in
            XCTAssertEqual(path, try self.temporaryPath())

            try self.simulateSPMOutput(at: path)
        }

        // When
        try subject.update(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: depedencies
        )

        // Then
        XCTAssertDirectoryContentEqual(
            dependenciesDirectory,
            [
                Constants.DependenciesDirectory.lockfilesDirectoryName,
                Constants.DependenciesDirectory.swiftPackageManagerDirectoryName,
            ]
        )
        XCTAssertDirectoryContentEqual(
            lockfilesDirectory,
            [
                Constants.DependenciesDirectory.packageResolvedName,
            ]
        )
        XCTAssertDirectoryContentEqual(
            swiftPackageManagerDirectory,
            [
                "manifest.db",
                "workspace-state.json",
                "artifacts",
                "checkouts",
                "repositories",
            ]
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
            "Dependencies/Lockfiles/Package.resolved",
            "Dependencies/Lockfiles/OtherLockfile.lock",
            "Dependencies/SwiftPackageManager/Info.plist",
            "Dependencies/OtherDepedenciesManager/bar.bar",
        ])

        // When
        try subject.clean(dependenciesDirectory: dependenciesDirectory)

        // Then
        XCTAssertDirectoryContentEqual(
            dependenciesDirectory,
            [
                Constants.DependenciesDirectory.lockfilesDirectoryName,
                "OtherDepedenciesManager",
            ]
        )
        XCTAssertDirectoryContentEqual(
            lockfilesDirectory,
            [
                "OtherLockfile.lock",
            ]
        )
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
