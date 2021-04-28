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

        let depedencies = SwiftPackageManagerDependencies([
            .remote(url: "https://github.com/Alamofire/Alamofire.git", requirement: .upToNextMajor("5.2.0")),
        ])

        swiftPackageManager.resolveStub = { [unowned self] path in
            XCTAssertEqual(path, try self.temporaryPath())

            try simulateSPMOutput(at: path)
        }

        // When
        try subject.fetch(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: depedencies
        )

        // Then
        let expectedPackageResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.packageResolvedName)
        let expectedSwiftPackageManagerDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)

        XCTAssertTrue(fileHandler.exists(expectedPackageResolvedPath))
        XCTAssertTrue(fileHandler.exists(expectedSwiftPackageManagerDirectory.appending(component: "manifest.db")))
        XCTAssertTrue(fileHandler.exists(expectedSwiftPackageManagerDirectory.appending(component: "workspace-state.json")))
        XCTAssertTrue(fileHandler.exists(expectedSwiftPackageManagerDirectory.appending(components: "artifacts", "foo.txt")))
        XCTAssertTrue(fileHandler.exists(expectedSwiftPackageManagerDirectory.appending(components: "checkouts", "Alamofire", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedSwiftPackageManagerDirectory.appending(components: "repositories", "checkouts-state.json")))
        XCTAssertTrue(fileHandler.exists(expectedSwiftPackageManagerDirectory.appending(components: "repositories", "Alamofire-e8f130fe", "config")))
    }

    func test_update() throws {
        // Given
        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)

        let depedencies = SwiftPackageManagerDependencies([
            .remote(url: "https://github.com/Alamofire/Alamofire.git", requirement: .upToNextMajor("5.2.0")),
        ])

        swiftPackageManager.updateStub = { [unowned self] path in
            XCTAssertEqual(path, try self.temporaryPath())

            try simulateSPMOutput(at: path)
        }

        // When
        try subject.update(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: depedencies
        )

        // Then
        let expectedPackageResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.packageResolvedName)
        let expectedSwiftPackageManagerDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)

        XCTAssertTrue(fileHandler.exists(expectedPackageResolvedPath))
        XCTAssertTrue(fileHandler.exists(expectedSwiftPackageManagerDirectory.appending(component: "manifest.db")))
        XCTAssertTrue(fileHandler.exists(expectedSwiftPackageManagerDirectory.appending(component: "workspace-state.json")))
        XCTAssertTrue(fileHandler.exists(expectedSwiftPackageManagerDirectory.appending(components: "artifacts", "foo.txt")))
        XCTAssertTrue(fileHandler.exists(expectedSwiftPackageManagerDirectory.appending(components: "checkouts", "Alamofire", "Info.plist")))
        XCTAssertTrue(fileHandler.exists(expectedSwiftPackageManagerDirectory.appending(components: "repositories", "checkouts-state.json")))
        XCTAssertTrue(fileHandler.exists(expectedSwiftPackageManagerDirectory.appending(components: "repositories", "Alamofire-e8f130fe", "config")))
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
