import Basic
import Foundation
import SPMUtility
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class SimulatorsControllerIntegrationTests: TuistTestCase {
    var subject: SimulatorsController!

    override func setUp() {
        super.setUp()
        subject = SimulatorsController()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    
    func test_runtimes_parses_simctl_output_and_returns_a_list_of_runtimes() throws {
        // Given
        let runtimes = try subject.runtimes()
        
        // Then
        XCTAssertNotEqual(runtimes.count, 0)
    }
}
