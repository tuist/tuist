import XCTest
import TSCBasic
import TuistCore
import TuistSupport

@testable import TuistDependencies
@testable import TuistSupportTesting

final class CartfileResolvedInteractorTests: TuistUnitTestCase {
    private var subject: CartfileResolvedInteractor!
    
    override func setUp() {
        super.setUp()
        
        subject = CartfileResolvedInteractor()
    }
    
    override func tearDown() {
        subject = nil
        
        super.tearDown()
    }
    
    func test_save_when_no_tuist_directory() throws {
        // Given
        let rootPath = try temporaryPath()
        
        try createFiles([
            "Temporary/Cartfile.resolved",
        ])
        
        // When
        try subject.save(at: rootPath, temporaryDirectoryPath: rootPath.appending(component: "Temporary"))
        
        // Then
        XCTAssertTrue(fileHandler.exists(rootPath.appending(components: "Tuist", "Dependencies", "Lockfiles", "Cartfile.resolved")))
    }
    
    func test_save_when_cartfile_already_saved() throws {
        // Given
        let rootPath = try temporaryPath()

        try createFiles([
            "Temporary/Cartfile.resolved",
            
            "Tuist/Dependencies/Lockfiles/Cartfile.resolved"
        ])
        try fileHandler.write("Message1", path: rootPath.appending(components: "Tuist", "Dependencies", "Lockfiles", "Cartfile.resolved"), atomically: true)
        try fileHandler.write("Message2", path: rootPath.appending(components: "Temporary", "Cartfile.resolved"), atomically: true)
        
        // When
        try subject.save(at: rootPath, temporaryDirectoryPath: rootPath.appending(component: "Temporary"))

        // Then
        XCTAssertTrue(fileHandler.exists(rootPath.appending(components: "Tuist", "Dependencies", "Lockfiles", "Cartfile.resolved")))
        XCTAssertEqual(
            try fileHandler.readTextFile(rootPath.appending(components: "Tuist", "Dependencies", "Lockfiles", "Cartfile.resolved")),
            "Message2"
        )
    }
    
    func test_load_when_cartfile_resolved_exist() throws {
        // Given
        let rootPath = try temporaryPath()

        try createFiles([
            "Tuist/Dependencies/Lockfiles/Cartfile.resolved"
        ])
        
        // When
        try subject.loadIfExist(from: rootPath, temporaryDirectoryPath: rootPath.appending(components: "Temporary"))
        
        // Then
        XCTAssertTrue(fileHandler.exists(rootPath.appending(components: "Temporary", "Cartfile.resolved")))
    }
    
    func test_load_when_cartfile_resolved_no_exist() throws {
        // Given
        let rootPath = try temporaryPath()

        try createFiles([
        ])
        
        // When
        XCTAssertNoThrow(try subject.loadIfExist(from: rootPath, temporaryDirectoryPath: rootPath.appending(components: "Temporary")))
        
        // Then
        XCTAssertFalse(fileHandler.exists(rootPath.appending(components: "Temporary", "Cartfile.resolved")))
    }
}
