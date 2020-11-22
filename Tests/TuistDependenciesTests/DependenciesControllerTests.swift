import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class DependenciesControllerTests: TuistUnitTestCase {
    private var subject: DependenciesController!

    private var carthageInteractor: MockCarthageInteractor!
    private var cocoapodsInteractor: MockCocoapodsInteractor!
    private var spmInteractor: MockSPMInteractor!

    override func setUp() {
        super.setUp()

        carthageInteractor = MockCarthageInteractor()
        cocoapodsInteractor = MockCocoapodsInteractor()
        spmInteractor = MockSPMInteractor()

        subject = DependenciesController(carthageInteractor: carthageInteractor,
                                         cocoapodsInteractor: cocoapodsInteractor,
                                         spmInteractor: spmInteractor)
    }

    override func tearDown() {
        subject = nil

        carthageInteractor = nil
        cocoapodsInteractor = nil
        spmInteractor = nil

        super.tearDown()
    }

    func test_install() throws {
        // Given
        let rootPath = try temporaryPath()
        let stubbedCarthageDependencies = [
            CarthageDependency(name: "Moya", requirement: .exact("1.1.1"), platforms: [.iOS]),
            CarthageDependency(name: "RxSwift", requirement: .exact("2.0.0"), platforms: [.iOS]),
        ]
        let stubbedDependencies = Dependencies(carthageDependencies: stubbedCarthageDependencies)
        let stubbedMethod = InstallDependenciesMethod.fetch

        // When
        try subject.install(at: rootPath, method: stubbedMethod, dependencies: stubbedDependencies)

        // Then
        XCTAssertTrue(carthageInteractor.invokedSave)
        XCTAssertEqual(carthageInteractor.invokedSaveParameters?.path, rootPath)
        XCTAssertEqual(carthageInteractor.invokedSaveParameters?.method, stubbedMethod)
        XCTAssertEqual(carthageInteractor.invokedSaveParameters?.dependencies, stubbedCarthageDependencies)
    }
}
