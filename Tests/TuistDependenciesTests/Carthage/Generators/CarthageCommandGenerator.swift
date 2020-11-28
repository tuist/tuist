import TuistCore
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class CarthageCommandGeneratorTests: TuistUnitTestCase {
    private var subject: CarthageCommandGenerator!
    
    override func setUp() {
        super.setUp()
        subject = CarthageCommandGenerator()
    }
    
    override func tearDown() {
        subject = nil
        super.tearDown()
    }
    
    func test_command_fetch() throws {
        // Given
        let stubbedPath = try temporaryPath()
        let expected = "carthage bootstrap --project-directory \(stubbedPath.pathString) --cache-builds --new-resolver"
        
        // When
        let got = subject
            .command(method: .fetch, path: stubbedPath, platforms: nil)
            .joined(separator: " ")
        
        // Then
        XCTAssertEqual(got, expected)
    }
    
    func test_command_fetch_with_platforms() throws {
        // Given
        let stubbedPath = try temporaryPath()
        let expected = "carthage bootstrap --project-directory \(stubbedPath.pathString) --platform iOS --cache-builds --new-resolver"
        
        // When
        let got = subject
            .command(method: .fetch, path: stubbedPath, platforms: [.iOS])
            .joined(separator: " ")
        
        // Then
        XCTAssertEqual(got, expected)
    }
    
    func test_command_update() throws {
        // Given
        let stubbedPath = try temporaryPath()
        let expected = "carthage update --project-directory \(stubbedPath.pathString) --cache-builds --new-resolver"
        
        // When
        let got = subject
            .command(method: .update, path: stubbedPath, platforms: nil)
            .joined(separator: " ")
        
        // Then
        XCTAssertEqual(got, expected)
    }
    
    func test_command_update_with_platforms() throws {
        // Given
        let stubbedPath = try temporaryPath()
        let expected = "carthage update --project-directory \(stubbedPath.pathString) --platform iOS --cache-builds --new-resolver"
        
        // When
        let got = subject
            .command(method: .update, path: stubbedPath, platforms: [.iOS])
            .joined(separator: " ")
        
        // Then
        XCTAssertEqual(got, expected)
    }
}
