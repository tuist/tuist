import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class DependenciesControllerTests: TuistUnitTestCase {
    private var subject: DependenciesController!

    private var swiftPackageManagerInteractor: MockSwiftPackageManagerInteractor!
    private var dependenciesGraphController: MockDependenciesGraphController!

    override func setUp() {
        super.setUp()

        swiftPackageManagerInteractor = MockSwiftPackageManagerInteractor()
        dependenciesGraphController = MockDependenciesGraphController()

        subject = DependenciesController(
            swiftPackageManagerInteractor: swiftPackageManagerInteractor,
            dependenciesGraphController: dependenciesGraphController
        )
    }

    override func tearDown() {
        subject = nil

        swiftPackageManagerInteractor = nil

        super.tearDown()
    }

    // MARK: - Fetch

    func test_fetch_swiftPackageManger() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<TuistGraph.PackagePlatform> = [.iOS]
        let swiftPackageManagerDependencies = SwiftPackageManagerDependencies(
            .packages([
                .remote(url: "Moya", requirement: .exact("2.3.4")),
                .remote(url: "Alamofire", requirement: .upToNextMajor("5.0.0")),
            ]),
            productTypes: [:],
            baseSettings: .default,
            targetSettings: [:]
        )
        let dependencies = Dependencies(
            swiftPackageManager: swiftPackageManagerDependencies,
            platforms: platforms
        )
        let swiftVersion = TSCUtility.Version(5, 4, 0)

        swiftPackageManagerInteractor.installStub = { arg0, arg1, arg2, arg3, arg4 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, swiftPackageManagerDependencies)
            XCTAssertEqual(arg2, [.iOS])
            XCTAssertFalse(arg3)
            XCTAssertEqual(arg4, TSCUtility.Version(5, 4, 0))
            return .test()
        }

        // When
        let graphManifest = try subject.fetch(at: rootPath, dependencies: dependencies, swiftVersion: swiftVersion)

        // Then
        XCTAssertEqual(graphManifest, .test())

        XCTAssertFalse(swiftPackageManagerInteractor.invokedClean)
        XCTAssertTrue(swiftPackageManagerInteractor.invokedInstall)
    }

    func test_fetch_throws_when_noPlatforms() throws {
        // Given
        let rootPath = try temporaryPath()

        let dependencies = TuistGraph.Dependencies(
            swiftPackageManager: .init(.packages([]), productTypes: [:], baseSettings: .default, targetSettings: [:]),
            platforms: []
        )

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.fetch(at: rootPath, dependencies: dependencies, swiftVersion: nil),
            DependenciesControllerError.noPlatforms
        )
    }

    func test_fetch_no_dependencies() throws {
        // Given
        let rootPath = try temporaryPath()

        let dependencies = TuistGraph.Dependencies(
            swiftPackageManager: .init(.packages([]), productTypes: [:], baseSettings: .default, targetSettings: [:]),
            platforms: [.iOS]
        )

        // When
        let graphManifest = try subject.fetch(at: rootPath, dependencies: dependencies, swiftVersion: nil)

        // Then
        XCTAssertEqual(graphManifest, .none)
    }

    // MARK: - Update

    func test_update_swiftPackageManger() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<TuistGraph.PackagePlatform> = [.iOS]
        let swiftPackageManagerDependencies = SwiftPackageManagerDependencies(
            .packages([
                .remote(url: "Moya", requirement: .exact("2.3.4")),
                .remote(url: "Alamofire", requirement: .upToNextMajor("5.0.0")),
            ]),
            productTypes: [:],
            baseSettings: .default,
            targetSettings: [:]
        )
        let dependencies = Dependencies(
            swiftPackageManager: swiftPackageManagerDependencies,
            platforms: platforms
        )
        let swiftVersion = TSCUtility.Version(5, 4, 0)

        swiftPackageManagerInteractor.installStub = { arg0, arg1, arg2, arg3, arg4 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, swiftPackageManagerDependencies)
            XCTAssertEqual(arg2, [.iOS])
            XCTAssertTrue(arg3)
            XCTAssertEqual(arg4, swiftVersion)
            return .test()
        }

        // When
        let graphManifest = try subject.update(at: rootPath, dependencies: dependencies, swiftVersion: swiftVersion)

        // Then
        XCTAssertEqual(graphManifest, .test())
        XCTAssertFalse(swiftPackageManagerInteractor.invokedClean)
        XCTAssertTrue(swiftPackageManagerInteractor.invokedInstall)
    }

    func test_update_throws_when_noPlatforms() throws {
        // Given
        let rootPath = try temporaryPath()

        let dependencies = TuistGraph.Dependencies(
            swiftPackageManager: .init(.packages([]), productTypes: [:], baseSettings: .default, targetSettings: [:]),
            platforms: []
        )

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.update(at: rootPath, dependencies: dependencies, swiftVersion: nil),
            DependenciesControllerError.noPlatforms
        )
    }

    func test_update_no_dependencies() throws {
        // Given
        let rootPath = try temporaryPath()

        let dependencies = TuistGraph.Dependencies(
            swiftPackageManager: .init(.packages([]), productTypes: [:], baseSettings: .default, targetSettings: [:]),
            platforms: [.iOS]
        )

        // When
        let graphManifest = try subject.update(at: rootPath, dependencies: dependencies, swiftVersion: nil)

        // Then
        XCTAssertEqual(graphManifest, .none)
    }

    func test_save() throws {
        // Given
        let rootPath = try temporaryPath()

        let dependenciesGraph = TuistGraph.DependenciesGraph(
            externalDependencies: [
                "library": [.xcframework(path: "/library.xcframework", status: .required)],
                "anotherLibrary": [.project(target: "Target", path: "/anotherLibrary")],
            ],
            externalProjects: [
                "/anotherLibrary": .test(),
            ]
        )

        dependenciesGraphController.saveStub = { arg0, arg1 in
            XCTAssertEqual(arg0, dependenciesGraph)
            XCTAssertEqual(arg1, rootPath)
        }

        // When
        try subject.save(dependenciesGraph: dependenciesGraph, to: rootPath)

        // Then
        XCTAssertFalse(dependenciesGraphController.invokedClean)
        XCTAssertTrue(dependenciesGraphController.invokedSave)
    }

    func test_save_no_dependencies() throws {
        // Given
        let rootPath = try temporaryPath()

        dependenciesGraphController.saveStub = { arg0, arg1 in
            XCTAssertEqual(arg0, .none)
            XCTAssertEqual(arg1, rootPath)
        }

        // When
        try subject.save(dependenciesGraph: .none, to: rootPath)

        // Then
        XCTAssertFalse(dependenciesGraphController.invokedClean)
        XCTAssertTrue(dependenciesGraphController.invokedSave)
    }
}
