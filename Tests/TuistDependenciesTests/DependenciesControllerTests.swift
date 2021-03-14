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

        let carthageDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
                .github(path: "RxSwift", requirement: .exact("2.0.0")),
            ],
            platforms: [.iOS],
            options: [.useXCFrameworks, .noUseBinaries]
        )
        let dependencies = Dependencies(carthage: carthageDependencies, swiftPackageManager: nil)

        // When
        try subject.fetch(at: rootPath, dependencies: dependencies)

        // Then
        XCTAssertTrue(carthageInteractor.invokedFetch)
        XCTAssertEqual(carthageInteractor.invokedFetchParameters?.dependenciesDirectory, dependenciesDirectoryPath)
        XCTAssertEqual(carthageInteractor.invokedFetchParameters?.dependencies, carthageDependencies)

        XCTAssertFalse(swiftPackageManagerInteractor.invokedFetch)
        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
    }

    func test_fetch_swiftPackageManger() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let swiftPackageManagerDependencies = SwiftPackageManagerDependencies(
            [
                .remote(url: "Moya", requirement: .exact("2.3.4")),
                .remote(url: "Alamofire", requirement: .upToNextMajor("5.0.0")),
            ]
        )
        let dependencies = Dependencies(carthage: nil, swiftPackageManager: swiftPackageManagerDependencies)

        // When
        try subject.fetch(at: rootPath, dependencies: dependencies)

        // Then
        XCTAssertTrue(swiftPackageManagerInteractor.invokedFetch)
        XCTAssertEqual(swiftPackageManagerInteractor.invokedFetchParameters?.dependenciesDirectory, dependenciesDirectoryPath)
        XCTAssertEqual(swiftPackageManagerInteractor.invokedFetchParameters?.dependencies, swiftPackageManagerDependencies)

        XCTAssertFalse(carthageInteractor.invokedFetch)
        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
    }

    func test_fetch_carthage_swiftPackageManger() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let carthageDependencies = CarthageDependencies(
            [
                .github(path: "Moya", requirement: .exact("1.1.1")),
                .github(path: "RxSwift", requirement: .exact("2.0.0")),
            ],
            platforms: [.iOS],
            options: [.useXCFrameworks, .noUseBinaries]
        )
        let swiftPackageManagerDependencies = SwiftPackageManagerDependencies(
            [
                .remote(url: "Moya", requirement: .exact("2.3.4")),
                .remote(url: "Alamofire", requirement: .upToNextMajor("5.0.0")),
            ]
        )
        let dependencies = Dependencies(carthage: carthageDependencies, swiftPackageManager: swiftPackageManagerDependencies)

        // When
        try subject.fetch(at: rootPath, dependencies: dependencies)

        // Then
        XCTAssertTrue(carthageInteractor.invokedFetch)
        XCTAssertEqual(carthageInteractor.invokedFetchParameters?.dependenciesDirectory, dependenciesDirectoryPath)
        XCTAssertEqual(carthageInteractor.invokedFetchParameters?.dependencies, carthageDependencies)

        XCTAssertTrue(swiftPackageManagerInteractor.invokedFetch)
        XCTAssertEqual(swiftPackageManagerInteractor.invokedFetchParameters?.dependenciesDirectory, dependenciesDirectoryPath)
        XCTAssertEqual(swiftPackageManagerInteractor.invokedFetchParameters?.dependencies, swiftPackageManagerDependencies)

        XCTAssertFalse(cocoaPodsInteractor.invokedFetch)
    }
}
