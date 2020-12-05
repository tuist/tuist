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
    
    func test_saveVersionFiles() throws {
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
        try subject.saveVersionFiles(carthageBuildDirectory: carthageBuildDirectory, dependenciesDirectory: dependenciesDirectory)
        
        // Then
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: ".Derived", "Carthage", ".Alamofire.version")))
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: ".Derived", "Carthage", ".RxSwift.version")))
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: ".Derived", "Carthage", ".Moya.version")))
    }
    
    func test_loadVersionFiles() throws {
        // Given
        let rootPath = try temporaryPath()
        let carthageBuildDirectory = rootPath.appending(components: "Temporary", "Carthage", "Build")
        let dependenciesDirectory = rootPath.appending(components: Constants.tuistDirectoryName, Constants.DependenciesDirectory.name)
        
        try createFiles([
            "Tuist/Dependencies/.Derived/Carthage/.Alamofire.version",
            "Tuist/Dependencies/.Derived/Carthage/.RxSwift.version",
            "Tuist/Dependencies/.Derived/Carthage/.Moya.version",
        ])
        
        // When
        try subject.loadVersionFiles(carthageBuildDirectory: carthageBuildDirectory, dependenciesDirectory: dependenciesDirectory)
        
        // Then
        XCTAssertTrue(fileHandler.exists(carthageBuildDirectory.appending(components: ".Alamofire.version")))
        XCTAssertTrue(fileHandler.exists(carthageBuildDirectory.appending(components: ".RxSwift.version")))
        XCTAssertTrue(fileHandler.exists(carthageBuildDirectory.appending(components: ".Moya.version")))
    }
}
