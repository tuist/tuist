import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class CarthageTests: TuistUnitTestCase {
    private var subject: Carthage!

    override func setUp() {
        super.setUp()

        subject = Carthage()
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }
    
    func test_bootstrap() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "carthage",
            "bootstrap",
            "--project-directory",
            path.pathString,
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
        ])
        
        // When / Then
        XCTAssertNoThrow(try subject.bootstrap(at: path, platforms: nil, options: nil))
    }
    
    func test_bootstrap_with_platforms() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "carthage",
            "bootstrap",
            "--project-directory",
            path.pathString,
            "--platform",
            "iOS",
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
        ])
        
        // When / Then
        XCTAssertNoThrow(try subject.bootstrap(at: path, platforms: [.iOS], options: nil))
    }
    
    func test_bootstrap_with_platforms_and_options() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "carthage",
            "bootstrap",
            "--project-directory",
            path.pathString,
            "--platform",
            "iOS",
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
            "--use-xcframeworks",
            "--no-use-binaries",
        ])
        
        // When / Then
        XCTAssertNoThrow(try subject.bootstrap(at: path, platforms: [.iOS], options: [.noUseBinaries, .useXCFrameworks]))
    }
    
    func test_update() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "carthage",
            "update",
            "--project-directory",
            path.pathString,
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
        ])
        
        // When / Then
        XCTAssertNoThrow(try subject.update(at: path, platforms: nil, options: nil))
    }
    
    func test_update_with_platforms() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "carthage",
            "update",
            "--project-directory",
            path.pathString,
            "--platform",
            "iOS",
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
        ])
        
        // When / Then
        XCTAssertNoThrow(try subject.update(at: path, platforms: [.iOS], options: nil))
    }
    
    func test_update_with_platforms_and_options() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "carthage",
            "update",
            "--project-directory",
            path.pathString,
            "--platform",
            "iOS",
            "--use-netrc",
            "--cache-builds",
            "--new-resolver",
            "--use-xcframeworks",
            "--no-use-binaries",
        ])
        
        // When / Then
        XCTAssertNoThrow(try subject.update(at: path, platforms: [.iOS], options: [.noUseBinaries, .useXCFrameworks]))
    }
}
