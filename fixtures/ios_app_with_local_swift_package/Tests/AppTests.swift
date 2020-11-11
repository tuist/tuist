import Foundation
import XCTest
import LibraryA

@testable import App

final class AppTests: XCTestCase {
    func testApp() {
        // Given
        let a = LibraryAClass()
        let subject = MyAppClass(a: a)

        // When
        let result = subject.text()

        // Then
        XCTAssertEqual(result, "MyAppClass.LibraryAClass")
    }
}
