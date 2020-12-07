import Foundation
import TSCBasic
import TuistScaffold
import TuistSupport
import XCTest
import TuistCore

@testable import TuistKit
@testable import TuistCoreTesting
@testable import TuistLoaderTesting
@testable import TuistScaffoldTesting
@testable import TuistSupportTesting

final class InspectServiceErrorTests: TuistUnitTestCase {
    func test_type() {
        XCTAssertEqual(InspectServiceError.targetNotFound(name: "test").type, .abort)
    }
    
    func test_description()  {
        XCTAssertEqual(InspectServiceError.targetNotFound(name: "test").description, "The target 'test' was not found.")

    }
}

final class InspectServiceTests: TuistUnitTestCase {
    var generator: MockGenerator!
    var subject: InspectService!
    
    override func setUp() {
        super.setUp()
        generator = MockGenerator()
        subject = InspectService(generator: generator)
    }
    
    func test_run() {
        // Given
        let graph = Graph.test()
        
        
        
    }
    
}
