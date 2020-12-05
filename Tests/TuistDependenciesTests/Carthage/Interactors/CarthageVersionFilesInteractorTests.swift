import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class CarthageVersionFilesInteractorTests: TuistUnitTestCase {
    private var subject: CarthageVersionFilesInteractor!
    
    override func setUp() {
        super.setUp()

        subject = CarthageVersionFilesInteractor()
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }
    
    func test_copyVersionFiles() throws {
        // Given
        let rootPath = try temporaryPath()
        let carthageBuildDirectory = rootPath.appending(components: "Temporary", "Carthage", "Build")
        let dependenciesDirectory = rootPath.appending(components: Constants.tuistDirectoryName, Constants.DependenciesDirectory.name)
        
        try createFiles([
            "Temporary/Carthage/Build/.Alamofire.version",
            "Temporary/Carthage/Build/.RxSwift.version",
            "Temporary/Carthage/Build/.Moya.version",
        ])
        
        // When
        try subject.copyVersionFiles(carthageBuildDirectory: carthageBuildDirectory, dependenciesDirectory: dependenciesDirectory)
        
        // Then
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: ".Derived", "Carthage", ".Alamofire.version")))
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: ".Derived", "Carthage", ".RxSwift.version")))
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: ".Derived", "Carthage", ".Moya.version")))
    }
}
