import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class CarthageInteractorTests: TuistUnitTestCase {
    private var subject: CarthageInteractor!

    private var fileHandlerMock: MockFileHandler!
    private var carthageCommandGenerator: MockCarthageCommandGenerator!
    private var cartfileContentGenerator: MockCartfileContentGenerator!
    private var carthageFrameworksInteractor: MockCarthageFrameworksInteractor!

    private var temporaryDirectoryPath: AbsolutePath!

    override func setUp() {
        super.setUp()

        do {
            temporaryDirectoryPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        } catch {
            XCTFail("Failed to setup TemporaryDirectory")
        }

        fileHandlerMock = MockFileHandler(temporaryDirectory: { self.temporaryDirectoryPath })
        carthageCommandGenerator = MockCarthageCommandGenerator()
        cartfileContentGenerator = MockCartfileContentGenerator()
        carthageFrameworksInteractor = MockCarthageFrameworksInteractor()

        subject = CarthageInteractor(fileHandler: fileHandlerMock,
                                     carthageCommandGenerator: carthageCommandGenerator,
                                     cartfileContentGenerator: cartfileContentGenerator,
                                     carthageFrameworksInteractor: carthageFrameworksInteractor)
    }

    override func tearDown() {
        carthageCommandGenerator = nil
        cartfileContentGenerator = nil
        carthageFrameworksInteractor = nil
        fileHandlerMock = nil

        temporaryDirectoryPath = nil

        subject = nil

        super.tearDown()
    }

    func test_install() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectory = rootPath
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)
        let carthageBuildDirectory = temporaryDirectoryPath
            .appending(components: "Carthage", "Build")
        
        try fileHandler.touch(temporaryDirectoryPath.appending(components: Constants.DependenciesDirectory.cartfileResolvedName))
        
        let stubbedDependencies = [
            CarthageDependency(name: "Moya", requirement: .exact("1.1.1"), platforms: [.iOS]),
            CarthageDependency(name: "RxSwift", requirement: .exact("2.0.0"), platforms: [.iOS]),
        ]
        let stubbedCommand = ["carthage", "bootstrap", "--project-directory", temporaryDirectoryPath.pathString, "--platform iOS", "--cache-builds", "--new-resolver"]
        
        carthageCommandGenerator.commandStub = { _, _, _ in stubbedCommand }

        system.whichStub = { _ in "1.0.0" }
        system.succeedCommand(stubbedCommand)

        // When
        try subject.install(dependenciesDirectory: dependenciesDirectory, method: .fetch, dependencies: stubbedDependencies)

        // Then
        let expectedCartfileResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
        
        XCTAssertTrue(fileHandler.exists(expectedCartfileResolvedPath))
        
        XCTAssertTrue(carthageCommandGenerator.invokedCommand)
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.method, .fetch)
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.path, temporaryDirectoryPath)
        XCTAssertEqual(carthageCommandGenerator.invokedCommandParameters?.platforms, [.iOS])
        
        XCTAssertTrue(cartfileContentGenerator.invokedCartfileContent)
        XCTAssertEqual(cartfileContentGenerator.invokedCartfileContentParameters, stubbedDependencies)

        XCTAssertTrue(carthageFrameworksInteractor.invokedCopyFrameworks)
        XCTAssertEqual(carthageFrameworksInteractor.invokedCopyFrameworksParameters?.carthageBuildDirectory, carthageBuildDirectory)
        XCTAssertEqual(carthageFrameworksInteractor.invokedCopyFrameworksParameters?.destinationDirectory, dependenciesDirectory)
    }
}
