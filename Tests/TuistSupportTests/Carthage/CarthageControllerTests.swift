import Foundation
import struct TSCUtility.Version
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class CarthageControllerTests: TuistUnitTestCase {
    private var subject: CarthageController!
    
    override func setUp() {
        super.setUp()
        subject = CarthageController()
    }
    
    override func tearDown() {
        subject = nil
        super.tearDown()
    }
    
    func test_canUseSystemCarthage_available() {
        // Given
        system.whichStub = { _ in "path" }
        
        // When / Then
        XCTAssertTrue(subject.canUseSystemCarthage())
    }
    
    func test_canUseSystemCarthage_unavailable() {
        // Given
        system.whichStub = { _ in throw NSError.test() }
        
        // When / Then
        XCTAssertFalse(subject.canUseSystemCarthage())
    }
    
    func test_carthageVersion_carthageNotFound() {
        // Given
        system.errorCommand("/usr/bin/env", "carthage", "version")
        
        // When / Then
        XCTAssertThrowsSpecific(try subject.carthageVersion(), CarthageControllerError.carthageNotFound)
    }
    
    func test_carthageVersion_success() {
        // Given
        system.stubs["/usr/bin/env carthage version"] = (stderror: nil, stdout: "0.37.0", exitstatus: 0)
        
        // When / Then
        XCTAssertEqual(try subject.carthageVersion(), Version(0, 37, 0))
    }
    
    func test_isXCFrameworksProductionSupported_notSupported() {
        // Given
        system.stubs["/usr/bin/env carthage version"] = (stderror: nil, stdout: "0.36.1", exitstatus: 0)
        
        // When / Then
        XCTAssertFalse(try subject.isXCFrameworksProductionSupported())
    }
    
    func test_isXCFrameworksProductionSupported_supported() {
        // Given
        system.stubs["/usr/bin/env carthage version"] = (stderror: nil, stdout: "0.37.0", exitstatus: 0)
        
        // When / Then
        XCTAssertTrue(try subject.isXCFrameworksProductionSupported())
    }
}
