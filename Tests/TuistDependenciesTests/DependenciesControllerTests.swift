import ProjectDescription
import TSCBasic
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class DependenciesControllerTests: TuistUnitTestCase {
    private var subject: DependenciesController!

    private var carthageInteractor: MockCarthageInteractor!
    private var cocoaPodsInteractor: MockCocoaPodsInteractor!
    private var swiftPackageManagerInteractor: MockSwiftPackageManagerInteractor!

    override func setUp() {
        super.setUp()

        carthageInteractor = MockCarthageInteractor()
        cocoaPodsInteractor = MockCocoaPodsInteractor()
        swiftPackageManagerInteractor = MockSwiftPackageManagerInteractor()

        subject = DependenciesController(
            carthageInteractor: carthageInteractor,
            cocoaPodsInteractor: cocoaPodsInteractor,
            swiftPackageManagerInteractor: swiftPackageManagerInteractor
        )
    }

    override func tearDown() {
        subject = nil

        carthageInteractor = nil
        cocoaPodsInteractor = nil
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

        let expectedGraphManifest = ProjectDescription.DependenciesGraph.testXCFramework(name: "Name")

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

        XCTAssertFalse(cocoaPodsInteractor.invokedClean)
        XCTAssertFalse(cocoaPodsInteractor.invokedInstall)
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
            ]
        )
        let dependencies = Dependencies(
            carthage: nil,
            swiftPackageManager: swiftPackageManagerDependencies,
            platforms: platforms
        )
        let swiftVersion = "5.4.0"

        swiftPackageManagerInteractor.installStub = { arg0, arg1, arg2, arg3, arg4 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, swiftPackageManagerDependencies)
            XCTAssertEqual(arg2, [.iOS])
            XCTAssertFalse(arg3)
            XCTAssertEqual(arg4, swiftVersion)
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

        XCTAssertFalse(cocoaPodsInteractor.invokedClean)
        XCTAssertFalse(cocoaPodsInteractor.invokedInstall)
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
            ]
        )
        let dependencies = Dependencies(
            carthage: carthageDependencies,
            swiftPackageManager: swiftPackageManagerDependencies,
            platforms: platforms
        )
        let swiftVersion = "5.4.0"
        let carthageGraph = ProjectDescription.DependenciesGraph.testXCFramework(name: "Carthage")
        let spmGraph = ProjectDescription.DependenciesGraph.testXCFramework(name: "SPM")

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
                    "Carthage": ProjectDescription.DependenciesGraph.testXCFramework(name: "Carthage").externalDependencies.values.first!,
                    "SPM": ProjectDescription.DependenciesGraph.testXCFramework(name: "SPM").externalDependencies.values.first!,
                ],
                externalProjects: [:]
            )
        )

        XCTAssertTrue(carthageInteractor.invokedInstall)
        XCTAssertFalse(carthageInteractor.invokedClean)

        XCTAssertTrue(swiftPackageManagerInteractor.invokedInstall)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedClean)

        XCTAssertFalse(cocoaPodsInteractor.invokedClean)
        XCTAssertFalse(cocoaPodsInteractor.invokedInstall)
    }

    func test_fetch_carthage_swiftPackageManger_throws_when_duplicatedDependency() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependencies = Dependencies(
            carthage: .init([
                .github(path: "Moya", requirement: .exact("1.1.1")),
            ]),
            swiftPackageManager: .init([
                .remote(url: "Moya", requirement: .exact("2.3.4")),
            ]),
            platforms: [.iOS]
        )
        let carthageGraph = ProjectDescription.DependenciesGraph.testXCFramework(
            name: "Duplicated",
            path: Path(rootPath.appending(component: "Carthage").pathString)
        )
        let spmGraph = ProjectDescription.DependenciesGraph.testXCFramework(
            name: "Duplicated",
            path: Path(rootPath.appending(component: "SPM").pathString)
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
                carthageGraph.externalDependencies.values.first!,
                spmGraph.externalDependencies.values.first!
            )
        )

        // Then
        XCTAssertTrue(carthageInteractor.invokedInstall)
        XCTAssertFalse(carthageInteractor.invokedClean)

        XCTAssertTrue(swiftPackageManagerInteractor.invokedInstall)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedClean)

        XCTAssertFalse(cocoaPodsInteractor.invokedClean)
        XCTAssertFalse(cocoaPodsInteractor.invokedInstall)
    }

    func test_fetch_throws_when_noPlatforms() throws {
        // Given
        let rootPath = try temporaryPath()

        let dependencies = Dependencies(
            carthage: .init([]),
            swiftPackageManager: .init([]),
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

        let dependencies = Dependencies(
            carthage: .init([]),
            swiftPackageManager: .init([]),
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

        XCTAssertFalse(cocoaPodsInteractor.invokedClean)
        XCTAssertFalse(cocoaPodsInteractor.invokedInstall)
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
        let expectedGraph = ProjectDescription.DependenciesGraph.testXCFramework(name: "Name")

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

        XCTAssertFalse(cocoaPodsInteractor.invokedClean)
        XCTAssertFalse(cocoaPodsInteractor.invokedInstall)
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
            ]
        )
        let dependencies = Dependencies(
            carthage: nil,
            swiftPackageManager: swiftPackageManagerDependencies,
            platforms: platforms
        )
        let swiftVersion = "5.4.0"

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

        XCTAssertFalse(cocoaPodsInteractor.invokedClean)
        XCTAssertFalse(cocoaPodsInteractor.invokedInstall)
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
            ]
        )
        let dependencies = Dependencies(
            carthage: carthageDependencies,
            swiftPackageManager: swiftPackageManagerDependencies,
            platforms: platforms
        )
        let swiftVersion = "5.4.0"
        let expectedGraph = ProjectDescription.DependenciesGraph.testXCFramework(name: "Name")

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

        XCTAssertFalse(cocoaPodsInteractor.invokedClean)
        XCTAssertFalse(cocoaPodsInteractor.invokedInstall)
    }

    func test_update_throws_when_noPlatforms() throws {
        // Given
        let rootPath = try temporaryPath()

        let dependencies = Dependencies(
            carthage: .init([]),
            swiftPackageManager: .init([]),
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

        let dependencies = Dependencies(
            carthage: .init([]),
            swiftPackageManager: .init([]),
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

        XCTAssertFalse(cocoaPodsInteractor.invokedClean)
        XCTAssertFalse(cocoaPodsInteractor.invokedInstall)
    }
}
