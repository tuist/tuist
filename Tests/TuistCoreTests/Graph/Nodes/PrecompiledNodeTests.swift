import Basic
import Foundation
import XCTest

import TuistSupportTesting
@testable import TuistCore

final class PrecompiledNodeTests: XCTestCase {
    var system: MockSystem!

    override func setUp() {
        super.setUp()
        system = MockSystem()
    }

    func test_name() {
        // Given
        let subject = PrecompiledNode(path: AbsolutePath("/Alamofire.framework"))

        // When
        let got = subject.name

        // Then
        XCTAssertEqual(got, "Alamofire")
    }
}
