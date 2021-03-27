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

    func test_fetch_carthage() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms = Set<Platform>([.iOS])
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

        // When
        try subject.fetch(at: rootPath, dependencies: dependencies)

        // Then
        XCTAssertFalse(carthageInteractor.invokedClean)
        XCTAssertTrue(carthageInteractor.invokedFetch)
        XCTAssertEqual(carthageInteractor.invokedFetchParameters?.dependenciesDirectory, dependenciesDirectoryPath)
        XCTAssertEqual(carthageInteractor.invokedFetchParameters?.dependencies, carthageDependencies)
        XCTAssertEqual(carthageInteractor.invokedFetchParameters?.platforms, platforms)

        XCTAssertTrue(swiftPackageManagerInteractor.invokedClean)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedFetch)
        
        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
    }

    func test_fetch_swiftPackageManger() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms = Set<Platform>([.iOS])
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

        // When
        try subject.fetch(at: rootPath, dependencies: dependencies)

        // Then
        XCTAssertFalse(swiftPackageManagerInteractor.invokedClean)
        XCTAssertTrue(swiftPackageManagerInteractor.invokedFetch)
        XCTAssertEqual(swiftPackageManagerInteractor.invokedFetchParameters?.dependenciesDirectory, dependenciesDirectoryPath)
        XCTAssertEqual(swiftPackageManagerInteractor.invokedFetchParameters?.dependencies, swiftPackageManagerDependencies)
        XCTAssertEqual(swiftPackageManagerInteractor.invokedFetchParameters?.platforms, platforms)

        XCTAssertTrue(carthageInteractor.invokedClean)
        XCTAssertFalse(carthageInteractor.invokedFetch)
        
        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
    }

    func test_fetch_carthage_swiftPackageManger() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let platforms = Set<Platform>([.iOS])
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

        // When
        try subject.fetch(at: rootPath, dependencies: dependencies)

        // Then
        XCTAssertTrue(carthageInteractor.invokedFetch)
        XCTAssertEqual(carthageInteractor.invokedFetchParameters?.dependenciesDirectory, dependenciesDirectoryPath)
        XCTAssertEqual(carthageInteractor.invokedFetchParameters?.dependencies, carthageDependencies)
        XCTAssertEqual(carthageInteractor.invokedFetchParameters?.platforms, platforms)

        XCTAssertTrue(swiftPackageManagerInteractor.invokedFetch)
        XCTAssertEqual(swiftPackageManagerInteractor.invokedFetchParameters?.dependenciesDirectory, dependenciesDirectoryPath)
        XCTAssertEqual(swiftPackageManagerInteractor.invokedFetchParameters?.dependencies, swiftPackageManagerDependencies)
        XCTAssertEqual(swiftPackageManagerInteractor.invokedFetchParameters?.platforms, platforms)

        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
    }
    
    func test_fetch_no_depedencies() throws {
        // Given
        let rootPath = try temporaryPath()
        
        let dependencies = Dependencies(
            carthage: .init([], options: []),
            swiftPackageManager: .init([]),
            platforms: []
        )
        
        // When
        try subject.fetch(at: rootPath, dependencies: dependencies)
        
        // Then
        XCTAssertTrue(carthageInteractor.invokedClean)
        XCTAssertFalse(carthageInteractor.invokedFetch)
        
        XCTAssertTrue(swiftPackageManagerInteractor.invokedClean)
        XCTAssertFalse(swiftPackageManagerInteractor.invokedFetch)
        
        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
    }
}
