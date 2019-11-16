import Basic
import Foundation
import XCTest

@testable import TuistCore

final class CocoaPodsNodeTests: XCTestCase {
    func test_name() {
        // Given
        let path = AbsolutePath("/")
        let subject = CocoaPodsNode(path: path)

        // When
        let got = subject.name

        // Then
        XCTAssertEqual(got, "CocoaPods")
    }

    func test_isEqual_returnsTrue_when_thePathsAreTheSame() {
        // Given
        let lhs = CocoaPodsNode(path: AbsolutePath("/"))
        let rhs = CocoaPodsNode(path: AbsolutePath("/"))

        // Then
        XCTAssertEqual(lhs, rhs)
    }

    func test_isEqual_returnsFalse_when_thePathsAreTheSame() {
        // Given
        let lhs = CocoaPodsNode(path: AbsolutePath("/"))
        let rhs = CocoaPodsNode(path: AbsolutePath("/other"))

        // Then
        XCTAssertNotEqual(lhs, rhs)
    }
}
