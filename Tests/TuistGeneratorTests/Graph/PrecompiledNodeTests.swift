import Basic
import Foundation
import XCTest

import TuistCoreTesting
@testable import TuistGenerator

final class PrecompiledNodeTests: XCTestCase {
    var system: MockSystem!

    override func setUp() {
        super.setUp()
        system = MockSystem()
    }

    func test_architecture_rawValues() {
        XCTAssertEqual(PrecompiledNode.Architecture.x8664.rawValue, "x86_64")
        XCTAssertEqual(PrecompiledNode.Architecture.i386.rawValue, "i386")
        XCTAssertEqual(PrecompiledNode.Architecture.armv7.rawValue, "armv7")
        XCTAssertEqual(PrecompiledNode.Architecture.armv7s.rawValue, "armv7s")
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
