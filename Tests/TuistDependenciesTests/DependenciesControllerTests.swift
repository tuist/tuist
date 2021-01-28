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

        subject = DependenciesController(carthageInteractor: carthageInteractor,
                                         cocoaPodsInteractor: cocoaPodsInteractor,
                                         swiftPackageManagerInteractor: swiftPackageManagerInteractor)
    }

    override func tearDown() {
        subject = nil

        carthageInteractor = nil
        cocoaPodsInteractor = nil
        swiftPackageManagerInteractor = nil

        super.tearDown()
    }

    func test_fetch() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectoryPath = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)

        let stubbedCarthageDependencies = [
            CarthageDependency(origin: .github(path: "Moya"), requirement: .exact("1.1.1"), platforms: [.iOS]),
            CarthageDependency(origin: .github(path: "RxSwift"), requirement: .exact("2.0.0"), platforms: [.iOS]),
        ]
        let stubbedDependencies = Dependencies(carthageDependencies: stubbedCarthageDependencies, swiftPackageManagerDependencies: [])

        // When
        try subject.fetch(at: rootPath, dependencies: stubbedDependencies)

        // Then
        XCTAssertTrue(carthageInteractor.invokedFetch)
        XCTAssertEqual(carthageInteractor.invokedFetchParameters?.dependenciesDirectory, dependenciesDirectoryPath)
        XCTAssertEqual(carthageInteractor.invokedFetchParameters?.dependencies, stubbedCarthageDependencies)
    }
}
