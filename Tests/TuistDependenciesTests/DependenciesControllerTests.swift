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

    func test_install() throws {
        // Given
        let rootPath = try temporaryPath()
        let tuistDirectoryPath = rootPath.appending(components: Constants.tuistDirectoryName)
        
        let stubbedCarthageDependencies = [
            CarthageDependency(name: "Moya", requirement: .exact("1.1.1"), platforms: [.iOS]),
            CarthageDependency(name: "RxSwift", requirement: .exact("2.0.0"), platforms: [.iOS]),
        ]
        let stubbedDependencies = Dependencies(carthageDependencies: stubbedCarthageDependencies)
        let stubbedMethod = InstallDependenciesMethod.fetch

        // When
        try subject.install(at: rootPath, method: stubbedMethod, dependencies: stubbedDependencies)

        // Then
        XCTAssertTrue(carthageInteractor.invokedInstall)
        XCTAssertEqual(carthageInteractor.invokedInstallParameters?.tuistDirectoryPath, tuistDirectoryPath)
        XCTAssertEqual(carthageInteractor.invokedInstallParameters?.method, stubbedMethod)
        XCTAssertEqual(carthageInteractor.invokedInstallParameters?.dependencies, stubbedCarthageDependencies)
    }
}
