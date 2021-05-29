import TSCBasic
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

        let platforms: Set<Platform> = [.iOS]
        let carthageDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
                .github(path: "RxSwift", requirement: .exact("2.0.0")),
            ],
            options: [.useXCFrameworks, .noUseBinaries]
        )
        let dependencies = Dependencies(
            carthage: carthageDependencies,
            swiftPackageManager: nil,
            platforms: platforms
        )

        carthageInteractor.fetchStub = { arg0, arg1, arg2 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, carthageDependencies)
            XCTAssertEqual(arg2, platforms)
        }

        // When
        try subject.fetch(at: rootPath, dependencies: dependencies)

        // Then
        XCTAssertFalse(carthageInteractor.invokedClean)
        XCTAssertFalse(carthageInteractor.invokedUpdate)
        XCTAssertTrue(carthageInteractor.invokedFetch)

        XCTAssertTrue(swiftPackageManagerInteractor.invokedClean)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedUpdate)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedFetch)

        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
        XCTAssertFalse(cocoaPodsInteractor.invokedUpdate)
    }

    func test_fetch_swiftPackageManger() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<Platform> = [.iOS]
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

        swiftPackageManagerInteractor.fetchStub = { arg0, arg1 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, swiftPackageManagerDependencies)
        }

        // When
        try subject.fetch(at: rootPath, dependencies: dependencies)

        // Then
        XCTAssertFalse(swiftPackageManagerInteractor.invokedClean)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedUpdate)
        XCTAssertTrue(swiftPackageManagerInteractor.invokedFetch)

        XCTAssertTrue(carthageInteractor.invokedClean)
        XCTAssertFalse(carthageInteractor.invokedUpdate)
        XCTAssertFalse(carthageInteractor.invokedFetch)

        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
        XCTAssertFalse(cocoaPodsInteractor.invokedUpdate)
    }

    func test_fetch_carthage_swiftPackageManger() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<Platform> = [.iOS]
        let carthageDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
                .github(path: "RxSwift", requirement: .exact("2.0.0")),
            ],
            options: [.useXCFrameworks, .noUseBinaries]
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

        carthageInteractor.fetchStub = { arg0, arg1, arg2 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, carthageDependencies)
            XCTAssertEqual(arg2, platforms)
        }
        swiftPackageManagerInteractor.fetchStub = { arg0, arg1 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, swiftPackageManagerDependencies)
        }

        // When
        try subject.fetch(at: rootPath, dependencies: dependencies)

        // Then
        XCTAssertTrue(carthageInteractor.invokedFetch)
        XCTAssertFalse(carthageInteractor.invokedUpdate)
        XCTAssertFalse(carthageInteractor.invokedClean)

        XCTAssertTrue(swiftPackageManagerInteractor.invokedFetch)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedUpdate)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedClean)

        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
        XCTAssertFalse(cocoaPodsInteractor.invokedUpdate)
    }

    func test_fetch_throws_when_noPlatforms() throws {
        // Given
        let rootPath = try temporaryPath()

        let dependencies = Dependencies(
            carthage: .init([], options: []),
            swiftPackageManager: .init([]),
            platforms: []
        )

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.fetch(at: rootPath, dependencies: dependencies),
            DependenciesControllerError.noPlatforms
        )
    }

    func test_fetch_no_dependencies() throws {
        // Given
        let rootPath = try temporaryPath()

        let dependencies = Dependencies(
            carthage: .init([], options: []),
            swiftPackageManager: .init([]),
            platforms: [.iOS]
        )

        // When
        try subject.fetch(at: rootPath, dependencies: dependencies)

        // Then
        XCTAssertFalse(carthageInteractor.invokedFetch)
        XCTAssertFalse(carthageInteractor.invokedUpdate)
        XCTAssertTrue(carthageInteractor.invokedClean)

        XCTAssertFalse(swiftPackageManagerInteractor.invokedFetch)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedUpdate)
        XCTAssertTrue(swiftPackageManagerInteractor.invokedClean)

        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
        XCTAssertFalse(cocoaPodsInteractor.invokedUpdate)
    }

    // MARK: - Update

    func test_update_carthage() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<Platform> = [.iOS]
        let carthageDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
                .github(path: "RxSwift", requirement: .exact("2.0.0")),
            ],
            options: [.useXCFrameworks, .noUseBinaries]
        )
        let dependencies = Dependencies(
            carthage: carthageDependencies,
            swiftPackageManager: nil,
            platforms: platforms
        )

        carthageInteractor.updateStub = { arg0, arg1, arg2 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, carthageDependencies)
            XCTAssertEqual(arg2, platforms)
        }

        // When
        try subject.update(at: rootPath, dependencies: dependencies)

        // Then
        XCTAssertFalse(carthageInteractor.invokedClean)
        XCTAssertFalse(carthageInteractor.invokedFetch)
        XCTAssertTrue(carthageInteractor.invokedUpdate)

        XCTAssertTrue(swiftPackageManagerInteractor.invokedClean)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedUpdate)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedFetch)

        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
        XCTAssertFalse(cocoaPodsInteractor.invokedUpdate)
    }

    func test_update_swiftPackageManger() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<Platform> = [.iOS]
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

        swiftPackageManagerInteractor.fetchStub = { arg0, arg1 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, swiftPackageManagerDependencies)
        }

        // When
        try subject.update(at: rootPath, dependencies: dependencies)

        // Then
        XCTAssertFalse(swiftPackageManagerInteractor.invokedClean)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedFetch)
        XCTAssertTrue(swiftPackageManagerInteractor.invokedUpdate)

        XCTAssertTrue(carthageInteractor.invokedClean)
        XCTAssertFalse(carthageInteractor.invokedUpdate)
        XCTAssertFalse(carthageInteractor.invokedFetch)

        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
        XCTAssertFalse(cocoaPodsInteractor.invokedUpdate)
    }

    func test_update_carthage_swiftPackageManger() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms: Set<Platform> = [.iOS]
        let carthageDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
                .github(path: "RxSwift", requirement: .exact("2.0.0")),
            ],
            options: [.useXCFrameworks, .noUseBinaries]
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

        carthageInteractor.updateStub = { arg0, arg1, arg2 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, carthageDependencies)
            XCTAssertEqual(arg2, platforms)
        }
        swiftPackageManagerInteractor.fetchStub = { arg0, arg1 in
            XCTAssertEqual(arg0, dependenciesDirectoryPath)
            XCTAssertEqual(arg1, swiftPackageManagerDependencies)
        }

        // When
        try subject.update(at: rootPath, dependencies: dependencies)

        // Then
        XCTAssertFalse(carthageInteractor.invokedClean)
        XCTAssertFalse(carthageInteractor.invokedFetch)
        XCTAssertTrue(carthageInteractor.invokedUpdate)

        XCTAssertFalse(swiftPackageManagerInteractor.invokedClean)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedFetch)
        XCTAssertTrue(swiftPackageManagerInteractor.invokedUpdate)

        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
        XCTAssertFalse(cocoaPodsInteractor.invokedUpdate)
    }

    func test_update_throws_when_noPlatforms() throws {
        // Given
        let rootPath = try temporaryPath()

        let dependencies = Dependencies(
            carthage: .init([], options: []),
            swiftPackageManager: .init([]),
            platforms: []
        )

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.update(at: rootPath, dependencies: dependencies),
            DependenciesControllerError.noPlatforms
        )
    }

    func test_update_no_dependencies() throws {
        // Given
        let rootPath = try temporaryPath()

        let dependencies = Dependencies(
            carthage: .init([], options: []),
            swiftPackageManager: .init([]),
            platforms: [.iOS]
        )

        // When
        try subject.update(at: rootPath, dependencies: dependencies)

        // Then
        XCTAssertFalse(carthageInteractor.invokedFetch)
        XCTAssertFalse(carthageInteractor.invokedUpdate)
        XCTAssertTrue(carthageInteractor.invokedClean)

        XCTAssertFalse(swiftPackageManagerInteractor.invokedFetch)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedUpdate)
        XCTAssertTrue(swiftPackageManagerInteractor.invokedClean)

        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
        XCTAssertFalse(cocoaPodsInteractor.invokedUpdate)
    }
}
