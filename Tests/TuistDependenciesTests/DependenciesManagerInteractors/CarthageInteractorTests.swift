import XCTest
import TSCBasic
import TuistCore
import TuistSupport

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class CarthageInteractorTests: TuistUnitTestCase {
    private var subject: CarthageInteractor!
    
    private var fileHandlerMock: MockFileHandler!
    private var cartfileResolvedInteractor: MockCartfileResolvedInteractor!
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
        cartfileResolvedInteractor = MockCartfileResolvedInteractor()
        carthageFrameworksInteractor = MockCarthageFrameworksInteractor()
        
        subject = CarthageInteractor(fileHandler: fileHandlerMock,
                                     cartfileResolvedInteractor: cartfileResolvedInteractor,
                                     carthageFrameworksInteractor: carthageFrameworksInteractor)
    }
    
    override func tearDown() {
        cartfileResolvedInteractor = nil
        carthageFrameworksInteractor = nil
        fileHandlerMock = nil
        
        temporaryDirectoryPath = nil
        
        subject = nil
        
        super.tearDown()
    }
    
    func test_install() throws {
        // Given
        let rootPath = try temporaryPath()
        let stubbedDependencies = [
            CarthageDependency(name: "Moya", requirement: .exact("1.1.1"), platforms: [.iOS]),
            CarthageDependency(name: "RxSwift", requirement: .exact("2.0.0"), platforms: [.iOS])
        ]
        
        system.whichStub = { _ in "1.0.0" }
        system.succeedCommand(["carthage", "bootstrap", "--project-directory", temporaryDirectoryPath.pathString, "--platform iOS", "--cache-builds", "--new-resolver"])
        
        // When
        try subject.install(at: rootPath, method: .fetch, dependencies: stubbedDependencies)
        
        // Then
        XCTAssertTrue(cartfileResolvedInteractor.invokedLoadIfExist)
        XCTAssertEqual(cartfileResolvedInteractor.invokedLoadIfExistParameters?.path, rootPath)
        XCTAssertEqual(cartfileResolvedInteractor.invokedLoadIfExistParameters?.temporaryDirectoryPath, temporaryDirectoryPath)
        
        XCTAssertTrue(cartfileResolvedInteractor.invokedSave)
        XCTAssertEqual(cartfileResolvedInteractor.invokedSaveParameters?.path, rootPath)
        XCTAssertEqual(cartfileResolvedInteractor.invokedSaveParameters?.temporaryDirectoryPath, temporaryDirectoryPath)
        
        XCTAssertTrue(carthageFrameworksInteractor.invokedSave)
        XCTAssertEqual(carthageFrameworksInteractor.invokedSaveParameters?.path, rootPath)
        XCTAssertEqual(carthageFrameworksInteractor.invokedSaveParameters?.temporaryDirectoryPath, temporaryDirectoryPath)
    }
}
