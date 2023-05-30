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

    private var carthageInteractor: MockCarthageInteractor!
    private var swiftPackageManagerInteractor: MockSwiftPackageManagerInteractor!
    private var dependenciesGraphController: MockDependenciesGraphController!

    override func setUp() {
        super.setUp()

        carthageInteractor = MockCarthageInteractor()
        swiftPackageManagerInteractor = MockSwiftPackageManagerInteractor()
        dependenciesGraphController = MockDependenciesGraphController()

        subject = DependenciesController(
            carthageInteractor: carthageInteractor,
            swiftPackageManagerInteractor: swiftPackageManagerInteractor,
            dependenciesGraphController: dependenciesGraphController
        )
    }

    override func tearDown() {
        subject = nil

        carthageInteractor = nil
        swiftPackageManagerInteractor = nil

        super.tearDown()
    }

    // MARK: - Fetch

    func test_fetch_carthage() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<TuistGraph.Platform> = [.iOS]
        let carthageDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
                .github(path: "RxSwift", requirement: .exact("2.0.0")),
            ]
        )
        let dependencies = Dependencies(
            carthage: carthageDependencies,
            swiftPackageManager: nil,
            platforms: platforms
        )

        let expectedGraphManifest = TuistCore.DependenciesGraph.testXCFramework(name: "Name", platforms: [.iOS])

        carthageInteractor.installStub = { arg0, arg1, arg2, arg3 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, carthageDependencies)
            XCTAssertEqual(arg2, platforms)
            XCTAssertFalse(arg3)

            return expectedGraphManifest
        }

        // When
        let graphManifest = try subject.fetch(at: rootPath, dependencies: dependencies, swiftVersion: nil)

        // Then
        XCTAssertEqual(graphManifest, expectedGraphManifest)

        XCTAssertFalse(carthageInteractor.invokedClean)
        XCTAssertTrue(carthageInteractor.invokedInstall)

        XCTAssertTrue(swiftPackageManagerInteractor.invokedClean)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedInstall)
    }

    func test_fetch_swiftPackageManger() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<TuistGraph.Platform> = [.iOS]
        let swiftPackageManagerDependencies = SwiftPackageManagerDependencies(
            [
                .remote(url: "Moya", requirement: .exact("2.3.4")),
                .remote(url: "Alamofire", requirement: .upToNextMajor("5.0.0")),
            ],
            productTypes: [:],
            baseSettings: .default,
            targetSettings: [:]
        )
        let dependencies = Dependencies(
            carthage: nil,
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

        XCTAssertTrue(carthageInteractor.invokedClean)
        XCTAssertFalse(carthageInteractor.invokedInstall)
    }

    func test_fetch_carthage_swiftPackageManger() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<TuistGraph.Platform> = [.iOS]
        let carthageDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
                .github(path: "RxSwift", requirement: .exact("2.0.0")),
            ]
        )
        let swiftPackageManagerDependencies = SwiftPackageManagerDependencies(
            [
                .remote(url: "Moya", requirement: .exact("2.3.4")),
                .remote(url: "Alamofire", requirement: .upToNextMajor("5.0.0")),
            ],
            productTypes: [:],
            baseSettings: .default,
            targetSettings: [:]
        )
        let dependencies = Dependencies(
            carthage: carthageDependencies,
            swiftPackageManager: swiftPackageManagerDependencies,
            platforms: platforms
        )
        let swiftVersion = TSCUtility.Version(5, 4, 0)
        let carthageGraph = TuistCore.DependenciesGraph.testXCFramework(name: "Carthage", platforms: [.iOS])
        let spmGraph = TuistCore.DependenciesGraph.testXCFramework(name: "SPM", platforms: [.iOS])

        carthageInteractor.installStub = { arg0, arg1, arg2, arg3 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, carthageDependencies)
            XCTAssertEqual(arg2, platforms)
            XCTAssertFalse(arg3)

            return carthageGraph
        }
        swiftPackageManagerInteractor.installStub = { arg0, arg1, arg2, arg3, arg4 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, swiftPackageManagerDependencies)
            XCTAssertEqual(arg2, [.iOS])
            XCTAssertFalse(arg3)
            XCTAssertEqual(arg4, swiftVersion)
            return spmGraph
        }

        // When
        let graphManifest = try subject.fetch(at: rootPath, dependencies: dependencies, swiftVersion: swiftVersion)

        // Then
        XCTAssertEqual(
            graphManifest,
            .init(
                externalDependencies: [
                    .iOS: [
                        "Carthage": TuistCore.DependenciesGraph.testXCFramework(name: "Carthage", platforms: [.iOS])
                            .externalDependencies[.iOS]!.values.first!,
                        "SPM": TuistCore.DependenciesGraph.testXCFramework(name: "SPM", platforms: [.iOS])
                            .externalDependencies[.iOS]!.values.first!,
                    ],
                ],
                externalProjects: [:]
            )
        )

        XCTAssertTrue(carthageInteractor.invokedInstall)
        XCTAssertFalse(carthageInteractor.invokedClean)

        XCTAssertTrue(swiftPackageManagerInteractor.invokedInstall)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedClean)
    }

    func test_fetch_carthage_swiftPackageManger_throws_when_duplicatedDependency() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependencies = TuistGraph.Dependencies(
            carthage: .init(
                [
                    .github(path: "Moya", requirement: .exact("1.1.1")),
                ]
            ),
            swiftPackageManager: .init(
                [
                    .remote(url: "Moya", requirement: .exact("2.3.4")),
                ],
                productTypes: [:],
                baseSettings: .default,
                targetSettings: [:]
            ),
            platforms: [.iOS]
        )
        let carthageGraph = TuistCore.DependenciesGraph.testXCFramework(
            name: "Duplicated",
            path: Path(rootPath.appending(component: "Carthage").pathString),
            platforms: [.iOS]
        )
        let spmGraph = TuistCore.DependenciesGraph.testXCFramework(
            name: "Duplicated",
            path: Path(rootPath.appending(component: "SPM").pathString),
            platforms: [.iOS]
        )

        carthageInteractor.installStub = { _, _, _, _ in
            carthageGraph
        }
        swiftPackageManagerInteractor.installStub = { _, _, _, _, _ in
            spmGraph
        }

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.fetch(at: rootPath, dependencies: dependencies, swiftVersion: nil),
            DependenciesControllerError.duplicatedDependency(
                "Duplicated",
                carthageGraph.externalDependencies[.iOS]!.values.first!,
                spmGraph.externalDependencies[.iOS]!.values.first!
            )
        )

        // Then
        XCTAssertTrue(carthageInteractor.invokedInstall)
        XCTAssertFalse(carthageInteractor.invokedClean)

        XCTAssertTrue(swiftPackageManagerInteractor.invokedInstall)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedClean)
    }

    func test_fetch_throws_when_noPlatforms() throws {
        // Given
        let rootPath = try temporaryPath()

        let dependencies = TuistGraph.Dependencies(
            carthage: .init([]),
            swiftPackageManager: .init([], productTypes: [:], baseSettings: .default, targetSettings: [:]),
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
            carthage: .init([]),
            swiftPackageManager: .init([], productTypes: [:], baseSettings: .default, targetSettings: [:]),
            platforms: [.iOS]
        )

        // When
        let graphManifest = try subject.fetch(at: rootPath, dependencies: dependencies, swiftVersion: nil)

        // Then
        XCTAssertEqual(graphManifest, .none)
        XCTAssertFalse(carthageInteractor.invokedInstall)
        XCTAssertTrue(carthageInteractor.invokedClean)

        XCTAssertFalse(swiftPackageManagerInteractor.invokedInstall)
        XCTAssertTrue(swiftPackageManagerInteractor.invokedClean)
    }

    // MARK: - Update

    func test_update_carthage() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<TuistGraph.Platform> = [.iOS]
        let carthageDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
                .github(path: "RxSwift", requirement: .exact("2.0.0")),
            ]
        )
        let dependencies = Dependencies(
            carthage: carthageDependencies,
            swiftPackageManager: nil,
            platforms: platforms
        )
        let expectedGraph = TuistCore.DependenciesGraph.testXCFramework(name: "Name", platforms: [.iOS])

        carthageInteractor.installStub = { arg0, arg1, arg2, arg3 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, carthageDependencies)
            XCTAssertEqual(arg2, platforms)
            XCTAssertTrue(arg3)

            return expectedGraph
        }

        // When
        let graphManifest = try subject.update(at: rootPath, dependencies: dependencies, swiftVersion: nil)

        // Then
        XCTAssertEqual(graphManifest, expectedGraph)
        XCTAssertFalse(carthageInteractor.invokedClean)
        XCTAssertTrue(carthageInteractor.invokedInstall)

        XCTAssertTrue(swiftPackageManagerInteractor.invokedClean)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedInstall)
    }

    func test_update_swiftPackageManger() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<TuistGraph.Platform> = [.iOS]
        let swiftPackageManagerDependencies = SwiftPackageManagerDependencies(
            [
                .remote(url: "Moya", requirement: .exact("2.3.4")),
                .remote(url: "Alamofire", requirement: .upToNextMajor("5.0.0")),
            ],
            productTypes: [:],
            baseSettings: .default,
            targetSettings: [:]
        )
        let dependencies = Dependencies(
            carthage: nil,
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

        XCTAssertTrue(carthageInteractor.invokedClean)
        XCTAssertFalse(carthageInteractor.invokedInstall)
    }

    func test_update_carthage_swiftPackageManger() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<TuistGraph.Platform> = [.iOS]
        let carthageDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
                .github(path: "RxSwift", requirement: .exact("2.0.0")),
            ]
        )
        let swiftPackageManagerDependencies = SwiftPackageManagerDependencies(
            [
                .remote(url: "Moya", requirement: .exact("2.3.4")),
                .remote(url: "Alamofire", requirement: .upToNextMajor("5.0.0")),
            ],
            productTypes: [:],
            baseSettings: .default,
            targetSettings: [:]
        )
        let dependencies = Dependencies(
            carthage: carthageDependencies,
            swiftPackageManager: swiftPackageManagerDependencies,
            platforms: platforms
        )
        let swiftVersion = TSCUtility.Version(5, 4, 0)
        let expectedGraph = TuistCore.DependenciesGraph.testXCFramework(name: "Name", platforms: [.iOS])

        carthageInteractor.installStub = { arg0, arg1, arg2, arg3 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, carthageDependencies)
            XCTAssertEqual(arg2, platforms)
            XCTAssertTrue(arg3)

            return expectedGraph
        }
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
        XCTAssertEqual(graphManifest, expectedGraph)
        XCTAssertFalse(carthageInteractor.invokedClean)
        XCTAssertTrue(carthageInteractor.invokedInstall)

        XCTAssertFalse(swiftPackageManagerInteractor.invokedClean)
        XCTAssertTrue(swiftPackageManagerInteractor.invokedInstall)
    }

    func test_update_throws_when_noPlatforms() throws {
        // Given
        let rootPath = try temporaryPath()

        let dependencies = TuistGraph.Dependencies(
            carthage: .init([]),
            swiftPackageManager: .init([], productTypes: [:], baseSettings: .default, targetSettings: [:]),
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
            carthage: .init([]),
            swiftPackageManager: .init([], productTypes: [:], baseSettings: .default, targetSettings: [:]),
            platforms: [.iOS]
        )

        // When
        let graphManifest = try subject.update(at: rootPath, dependencies: dependencies, swiftVersion: nil)

        // Then
        XCTAssertEqual(graphManifest, .none)
        XCTAssertFalse(carthageInteractor.invokedInstall)
        XCTAssertTrue(carthageInteractor.invokedClean)

        XCTAssertFalse(swiftPackageManagerInteractor.invokedInstall)
        XCTAssertTrue(swiftPackageManagerInteractor.invokedClean)
    }

    func test_save() throws {
        // Given
        let rootPath = try temporaryPath()

        let dependenciesGraph = TuistGraph.DependenciesGraph(
            externalDependencies: [
                .iOS: [
                    "library": [.xcframework(path: "/library.xcframework")],
                    "anotherLibrary": [.project(target: "Target", path: "/anotherLibrary")],
                ],
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
